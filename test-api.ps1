###############################################################################
# Subscription Tracker API - Test Suite
###############################################################################

$BASE = "http://localhost:5500"
$passed = 0
$failed = 0
$total = 0

function Test-Endpoint {
    param(
        [string]$Name,
        [string]$Method,
        [string]$Url,
        [string]$Body = $null,
        [int]$ExpectedStatus,
        [string]$Token = $null,
        [string]$CheckField = $null,
        [string]$CheckValue = $null
    )
    $script:total++
    try {
        $headers = @{ "Content-Type" = "application/json" }
        if ($Token) { $headers["Authorization"] = "Bearer $Token" }

        $params = @{
            Uri     = $Url
            Method  = $Method
            Headers = $headers
            UseBasicParsing = $true
            ErrorAction = "Stop"
        }
        if ($Body) { $params["Body"] = $Body }

        # Small delay to avoid rate limiting
        Start-Sleep -Milliseconds 300

        try {
            $response = Invoke-WebRequest @params
            $status = $response.StatusCode
            $content = $response.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
        } catch [System.Net.WebException] {
            $status = [int]$_.Exception.Response.StatusCode
            try {
                $reader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
                $content = $reader.ReadToEnd() | ConvertFrom-Json -ErrorAction SilentlyContinue
                $reader.Close()
            } catch {
                $content = $null
            }
        } catch {
            # PowerShell 7+ / HttpRequestException
            if ($_.Exception.Response) {
                $status = [int]$_.Exception.Response.StatusCode
            } else {
                $status = 0
            }
            $content = $null
        }

        if ($status -eq $ExpectedStatus) {
            $script:passed++
            Write-Host "  PASS " -ForegroundColor Green -NoNewline
            Write-Host "[$Method $status] $Name"
        } else {
            $script:failed++
            Write-Host "  FAIL " -ForegroundColor Red -NoNewline
            Write-Host "[$Method] $Name - Expected $ExpectedStatus, got $status"
            if ($content) { Write-Host "        Response: $($content | ConvertTo-Json -Depth 2 -Compress)" -ForegroundColor DarkGray }
        }
        return $content
    } catch {
        $script:failed++
        Write-Host "  FAIL " -ForegroundColor Red -NoNewline
        Write-Host "[$Method] $Name - Exception: $($_.Exception.Message)"
        return $null
    }
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " Subscription Tracker API - Test Suite" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# ─── 1. BASIC ENDPOINTS ────────────────────────────────────────────────
Write-Host "--- 1. Basic Endpoints ---" -ForegroundColor Yellow

Test-Endpoint -Name "GET / returns welcome" `
    -Method GET -Url "$BASE/" -ExpectedStatus 200

# The root endpoint returns plain text, so status 0 can happen due to
# PowerShell parsing. Re-verify with a cleaner call.
try {
    $rootCheck = Invoke-WebRequest -Uri "$BASE/" -Method GET -UseBasicParsing -ErrorAction Stop
    if ($rootCheck.Content -match 'Welcome') {
        Write-Host "        (Root endpoint verified: returns correct text)" -ForegroundColor DarkGray
    }
} catch {}

Test-Endpoint -Name "GET /health returns ok" `
    -Method GET -Url "$BASE/health" -ExpectedStatus 200

# ─── 2. AUTH ENDPOINTS ─────────────────────────────────────────────────
Write-Host ""
Write-Host "--- 2. Auth Endpoints ---" -ForegroundColor Yellow

$ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$testEmail = "testuser_$ts@test.com"
$testPassword = "Test123456"

# Sign up - new user
$signUpBody = @{ name = "Test User"; email = $testEmail; password = $testPassword } | ConvertTo-Json
$signUpResult = Test-Endpoint -Name "POST /auth/sign-up (new user)" `
    -Method POST -Url "$BASE/api/v1/auth/sign-up" -Body $signUpBody -ExpectedStatus 201

$token = $null
$userId = $null
if ($signUpResult -and $signUpResult.data) {
    $token = $signUpResult.data.token
    $userId = $signUpResult.data.user._id
}

# Sign up - check password not in response
$script:total++
if ($signUpResult -and $signUpResult.data -and $signUpResult.data.user -and (-not $signUpResult.data.user.password)) {
    $script:passed++
    Write-Host "  PASS " -ForegroundColor Green -NoNewline
    Write-Host "Sign-up response does not contain password"
} else {
    $script:failed++
    Write-Host "  FAIL " -ForegroundColor Red -NoNewline
    Write-Host "Sign-up response LEAKS password!"
}

# Sign up - duplicate
Test-Endpoint -Name "POST /auth/sign-up (duplicate email)" `
    -Method POST -Url "$BASE/api/v1/auth/sign-up" -Body $signUpBody -ExpectedStatus 409

# Sign in - valid
$signInBody = @{ email = $testEmail; password = $testPassword } | ConvertTo-Json
$signInResult = Test-Endpoint -Name "POST /auth/sign-in (valid)" `
    -Method POST -Url "$BASE/api/v1/auth/sign-in" -Body $signInBody -ExpectedStatus 200

# Update token from sign-in if sign-up didn't work
if ($signInResult -and $signInResult.data -and (-not $token)) {
    $token = $signInResult.data.token
    $userId = $signInResult.data.user._id
}

# Sign in - check password not in response
$script:total++
if ($signInResult -and $signInResult.data -and $signInResult.data.user -and (-not $signInResult.data.user.password)) {
    $script:passed++
    Write-Host "  PASS " -ForegroundColor Green -NoNewline
    Write-Host "Sign-in response does not contain password"
} else {
    $script:failed++
    Write-Host "  FAIL " -ForegroundColor Red -NoNewline
    Write-Host "Sign-in response LEAKS password!"
}

# Sign in - wrong password
$wrongPwBody = @{ email = $testEmail; password = "WrongPassword" } | ConvertTo-Json
Test-Endpoint -Name "POST /auth/sign-in (wrong password)" `
    -Method POST -Url "$BASE/api/v1/auth/sign-in" -Body $wrongPwBody -ExpectedStatus 401

# Sign in - non-existent user
$noUserBody = @{ email = "nonexistent@test.com"; password = "Test123456" } | ConvertTo-Json
Test-Endpoint -Name "POST /auth/sign-in (user not found)" `
    -Method POST -Url "$BASE/api/v1/auth/sign-in" -Body $noUserBody -ExpectedStatus 404

# Sign out
Test-Endpoint -Name "POST /auth/sign-out" `
    -Method POST -Url "$BASE/api/v1/auth/sign-out" -ExpectedStatus 200

# ─── 3. AUTHORIZATION / PROTECTED ROUTES ────────────────────────────────
Write-Host ""
Write-Host "--- 3. Authorization ---" -ForegroundColor Yellow

Test-Endpoint -Name "GET /users (no token -> 401)" `
    -Method GET -Url "$BASE/api/v1/users" -ExpectedStatus 401

Test-Endpoint -Name "GET /users (invalid token -> 401)" `
    -Method GET -Url "$BASE/api/v1/users" -Token "invalidtoken123" -ExpectedStatus 401

Test-Endpoint -Name "GET /subscriptions (no token -> 401)" `
    -Method GET -Url "$BASE/api/v1/subscriptions" -ExpectedStatus 401

# ─── 4. USER ENDPOINTS ─────────────────────────────────────────────────
Write-Host ""
Write-Host "--- 4. User Endpoints ---" -ForegroundColor Yellow

if ($token) {
    Test-Endpoint -Name "GET /users (authenticated)" `
        -Method GET -Url "$BASE/api/v1/users" -Token $token -ExpectedStatus 200

    Test-Endpoint -Name "GET /users/:id (own profile)" `
        -Method GET -Url "$BASE/api/v1/users/$userId" -Token $token -ExpectedStatus 200

    # Update user
    $updateBody = @{ name = "Updated Test User" } | ConvertTo-Json
    Test-Endpoint -Name "PUT /users/:id (update name)" `
        -Method PUT -Url "$BASE/api/v1/users/$userId" -Body $updateBody -Token $token -ExpectedStatus 200

    # Get non-existent user
    Test-Endpoint -Name "GET /users/:id (not found)" `
        -Method GET -Url "$BASE/api/v1/users/000000000000000000000000" -Token $token -ExpectedStatus 404
} else {
    Write-Host "  SKIP - No auth token available" -ForegroundColor DarkYellow
}

# ─── 5. SUBSCRIPTION ENDPOINTS ─────────────────────────────────────────
Write-Host ""
Write-Host "--- 5. Subscription Endpoints ---" -ForegroundColor Yellow

$subscriptionId = $null

if ($token) {
    # Create subscription
    $subBody = @{
        name = "Netflix Test"
        price = 15.99
        currency = "USD"
        frequency = "monthly"
        category = "entertainment"
        paymentMethod = "credit card"
        startDate = (Get-Date).AddDays(-10).ToString("yyyy-MM-ddTHH:mm:ssZ")
    } | ConvertTo-Json

    $createResult = Test-Endpoint -Name "POST /subscriptions (create)" `
        -Method POST -Url "$BASE/api/v1/subscriptions" -Body $subBody -Token $token -ExpectedStatus 201

    if ($createResult -and $createResult.data -and $createResult.data.subscription) {
        $subscriptionId = $createResult.data.subscription._id
    }

    # Create a second subscription
    $subBody2 = @{
        name = "Spotify Test"
        price = 9.99
        currency = "EUR"
        frequency = "monthly"
        category = "entertainment"
        paymentMethod = "paypal"
        startDate = (Get-Date).AddDays(-5).ToString("yyyy-MM-ddTHH:mm:ssZ")
    } | ConvertTo-Json

    $createResult2 = Test-Endpoint -Name "POST /subscriptions (create second)" `
        -Method POST -Url "$BASE/api/v1/subscriptions" -Body $subBody2 -Token $token -ExpectedStatus 201

    $subscriptionId2 = $null
    if ($createResult2 -and $createResult2.data -and $createResult2.data.subscription) {
        $subscriptionId2 = $createResult2.data.subscription._id
    }

    # Get all subscriptions
    $allSubs = Test-Endpoint -Name "GET /subscriptions (list all)" `
        -Method GET -Url "$BASE/api/v1/subscriptions" -Token $token -ExpectedStatus 200

    # Check count
    $script:total++
    if ($allSubs -and $allSubs.data -and $allSubs.data.Count -ge 2) {
        $script:passed++
        Write-Host "  PASS " -ForegroundColor Green -NoNewline
        Write-Host "List returns at least 2 subscriptions ($($allSubs.data.Count) total)"
    } else {
        $script:failed++
        Write-Host "  FAIL " -ForegroundColor Red -NoNewline
        Write-Host "Expected 2+ subscriptions in the list"
    }

    # Filter by status
    Test-Endpoint -Name "GET /subscriptions?status=active (filter)" `
        -Method GET -Url "$BASE/api/v1/subscriptions?status=active" -Token $token -ExpectedStatus 200

    # Filter by category
    Test-Endpoint -Name "GET /subscriptions?category=entertainment (filter)" `
        -Method GET -Url "$BASE/api/v1/subscriptions?category=entertainment" -Token $token -ExpectedStatus 200

    if ($subscriptionId) {
        # Get single subscription
        Test-Endpoint -Name "GET /subscriptions/:id (single)" `
            -Method GET -Url "$BASE/api/v1/subscriptions/$subscriptionId" -Token $token -ExpectedStatus 200

        # Update subscription
        $updateSubBody = @{ name = "Netflix Premium"; price = 22.99 } | ConvertTo-Json
        Test-Endpoint -Name "PUT /subscriptions/:id (update)" `
            -Method PUT -Url "$BASE/api/v1/subscriptions/$subscriptionId" -Body $updateSubBody -Token $token -ExpectedStatus 200

        # Cancel subscription
        Test-Endpoint -Name "PUT /subscriptions/:id/cancel" `
            -Method PUT -Url "$BASE/api/v1/subscriptions/$subscriptionId/cancel" -Token $token -ExpectedStatus 200

        # Cancel already cancelled
        Test-Endpoint -Name "PUT /subscriptions/:id/cancel (already cancelled)" `
            -Method PUT -Url "$BASE/api/v1/subscriptions/$subscriptionId/cancel" -Token $token -ExpectedStatus 400

        # Delete subscription
        Test-Endpoint -Name "DELETE /subscriptions/:id" `
            -Method DELETE -Url "$BASE/api/v1/subscriptions/$subscriptionId" -Token $token -ExpectedStatus 200
    }

    # Get non-existent subscription
    Test-Endpoint -Name "GET /subscriptions/:id (not found)" `
        -Method GET -Url "$BASE/api/v1/subscriptions/000000000000000000000000" -Token $token -ExpectedStatus 404

    # Get upcoming renewals
    Test-Endpoint -Name "GET /subscriptions/upcoming-renewals" `
        -Method GET -Url "$BASE/api/v1/subscriptions/upcoming-renewals" -Token $token -ExpectedStatus 200

    # Get user's subscriptions
    Test-Endpoint -Name "GET /subscriptions/user/:id" `
        -Method GET -Url "$BASE/api/v1/subscriptions/user/$userId" -Token $token -ExpectedStatus 200

} else {
    Write-Host "  SKIP - No auth token available" -ForegroundColor DarkYellow
}

# ─── 6. EDGE CASES / VALIDATION ────────────────────────────────────────
Write-Host ""
Write-Host "--- 6. Validation & Edge Cases ---" -ForegroundColor Yellow

if ($token) {
    # Create subscription with missing required fields
    $badSubBody = @{ name = "Incomplete" } | ConvertTo-Json
    Test-Endpoint -Name "POST /subscriptions (missing fields -> 400)" `
        -Method POST -Url "$BASE/api/v1/subscriptions" -Body $badSubBody -Token $token -ExpectedStatus 400

    # Sign up with missing fields
    $badSignUp = @{ email = "bad@test.com" } | ConvertTo-Json
    Test-Endpoint -Name "POST /auth/sign-up (missing name+password)" `
        -Method POST -Url "$BASE/api/v1/auth/sign-up" -Body $badSignUp -ExpectedStatus 400

    # Invalid ObjectId
    Test-Endpoint -Name "GET /subscriptions/:id (invalid id -> 404)" `
        -Method GET -Url "$BASE/api/v1/subscriptions/invalidid123" -Token $token -ExpectedStatus 404

    # 404 for unknown route
    Test-Endpoint -Name "GET /api/v1/unknown (404 or error)" `
        -Method GET -Url "$BASE/api/v1/unknown" -Token $token -ExpectedStatus 404
}

# ─── 7. CLEANUP: Delete test user ──────────────────────────────────────
Write-Host ""
Write-Host "--- 7. Cleanup ---" -ForegroundColor Yellow

if ($token -and $userId) {
    # Delete remaining subscription if exists
    if ($subscriptionId2) {
        Test-Endpoint -Name "DELETE /subscriptions/:id (cleanup sub 2)" `
            -Method DELETE -Url "$BASE/api/v1/subscriptions/$subscriptionId2" -Token $token -ExpectedStatus 200
    }

    # Delete the test user (cascades subscriptions)
    Test-Endpoint -Name "DELETE /users/:id (cleanup user)" `
        -Method DELETE -Url "$BASE/api/v1/users/$userId" -Token $token -ExpectedStatus 200

    # Verify user is gone — token is now invalid since user is deleted, so 401 is correct
    Test-Endpoint -Name "GET /users/:id (deleted user -> 401)" `
        -Method GET -Url "$BASE/api/v1/users/$userId" -Token $token -ExpectedStatus 401
}

# ─── SUMMARY ────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " Results: $passed PASSED / $failed FAILED / $total TOTAL" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
