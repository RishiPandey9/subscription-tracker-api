import Subscription from '../models/subscription.model.js'
import { workflowClient } from '../config/upstash.js'
import { SERVER_URL } from '../config/env.js'

export const createSubscription = async (req, res, next) => {
  try {
    const subscription = await Subscription.create({
      ...req.body,
      user: req.user._id,
    });

    // Trigger workflow for renewal reminders (non-blocking)
    let workflowRunId = null;
    try {
      const result = await workflowClient.trigger({
        url: `${SERVER_URL}/api/v1/workflows/subscription/reminder`,
        body: {
          subscriptionId: subscription.id,
        },
        headers: {
          'content-type': 'application/json',
        },
        retries: 0,
      });
      workflowRunId = result.workflowRunId;
    } catch (workflowError) {
      console.error('Failed to trigger reminder workflow:', workflowError.message);
    }

    res.status(201).json({ success: true, data: { subscription, workflowRunId } });
  } catch (e) {
    next(e);
  }
}

export const getAllSubscriptions = async (req, res, next) => {
  try {
    const filter = { user: req.user._id };

    // Optional query filters
    if (req.query.status) filter.status = req.query.status;
    if (req.query.category) filter.category = req.query.category;

    const subscriptions = await Subscription.find(filter).sort({ createdAt: -1 });

    res.status(200).json({ success: true, data: subscriptions });
  } catch (e) {
    next(e);
  }
}

export const getSubscriptionById = async (req, res, next) => {
  try {
    const subscription = await Subscription.findById(req.params.id).populate('user', 'name email');

    if (!subscription) {
      const error = new Error('Subscription not found');
      error.statusCode = 404;
      throw error;
    }

    // Ensure the user owns this subscription
    if (subscription.user._id.toString() !== req.user.id) {
      const error = new Error('You are not authorized to view this subscription');
      error.statusCode = 403;
      throw error;
    }

    res.status(200).json({ success: true, data: subscription });
  } catch (e) {
    next(e);
  }
}

export const updateSubscription = async (req, res, next) => {
  try {
    const subscription = await Subscription.findById(req.params.id);

    if (!subscription) {
      const error = new Error('Subscription not found');
      error.statusCode = 404;
      throw error;
    }

    if (subscription.user.toString() !== req.user.id) {
      const error = new Error('You are not authorized to update this subscription');
      error.statusCode = 403;
      throw error;
    }

    // Only allow updating certain fields
    const allowedUpdates = ['name', 'price', 'currency', 'frequency', 'category', 'paymentMethod'];
    const updates = {};
    for (const key of allowedUpdates) {
      if (req.body[key] !== undefined) {
        updates[key] = req.body[key];
      }
    }

    const updatedSubscription = await Subscription.findByIdAndUpdate(
      req.params.id,
      updates,
      { new: true, runValidators: true }
    );

    res.status(200).json({ success: true, data: updatedSubscription });
  } catch (e) {
    next(e);
  }
}

export const cancelSubscription = async (req, res, next) => {
  try {
    const subscription = await Subscription.findById(req.params.id);

    if (!subscription) {
      const error = new Error('Subscription not found');
      error.statusCode = 404;
      throw error;
    }

    if (subscription.user.toString() !== req.user.id) {
      const error = new Error('You are not authorized to cancel this subscription');
      error.statusCode = 403;
      throw error;
    }

    if (subscription.status === 'cancelled') {
      const error = new Error('Subscription is already cancelled');
      error.statusCode = 400;
      throw error;
    }

    subscription.status = 'cancelled';
    await subscription.save();

    res.status(200).json({ success: true, message: 'Subscription cancelled successfully', data: subscription });
  } catch (e) {
    next(e);
  }
}

export const deleteSubscription = async (req, res, next) => {
  try {
    const subscription = await Subscription.findById(req.params.id);

    if (!subscription) {
      const error = new Error('Subscription not found');
      error.statusCode = 404;
      throw error;
    }

    if (subscription.user.toString() !== req.user.id) {
      const error = new Error('You are not authorized to delete this subscription');
      error.statusCode = 403;
      throw error;
    }

    await Subscription.findByIdAndDelete(req.params.id);

    res.status(200).json({ success: true, message: 'Subscription deleted successfully' });
  } catch (e) {
    next(e);
  }
}

export const getUpcomingRenewals = async (req, res, next) => {
  try {
    const daysAhead = parseInt(req.query.days) || 7;

    const now = new Date();
    const futureDate = new Date();
    futureDate.setDate(now.getDate() + daysAhead);

    const subscriptions = await Subscription.find({
      user: req.user._id,
      status: 'active',
      renewalDate: { $gte: now, $lte: futureDate },
    }).sort({ renewalDate: 1 });

    res.status(200).json({ success: true, data: subscriptions });
  } catch (e) {
    next(e);
  }
}

export const getUserSubscriptions = async (req, res, next) => {
  try {
    // Check if the user is the same as the one in the token
    if(req.user.id !== req.params.id) {
      const error = new Error('You are not the owner of this account');
      error.statusCode = 401;
      throw error;
    }

    const subscriptions = await Subscription.find({ user: req.params.id });

    res.status(200).json({ success: true, data: subscriptions });
  } catch (e) {
    next(e);
  }
}