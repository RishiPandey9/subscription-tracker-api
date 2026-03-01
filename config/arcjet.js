import arcjet, { shield, detectBot, tokenBucket } from "@arcjet/node";
import { ARCJET_KEY } from './env.js'

const aj = arcjet({
  key: ARCJET_KEY,
  characteristics: ["ip.src"],
  rules: [
    shield({ mode: "LIVE" }),
    detectBot({
      mode: "LIVE",
      allow: [ "CATEGORY:SEARCH_ENGINE" ],
    }),
    tokenBucket({
      mode: "LIVE",
      refillRate: 20, // Refill 20 tokens per interval
      interval: 10, // Refill every 10 seconds
      capacity: 50, // Bucket capacity of 50 tokens
    }),
  ],
});

export default aj;