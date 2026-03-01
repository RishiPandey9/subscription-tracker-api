import mongoose from 'mongoose';
import bcrypt from 'bcryptjs';
import User from '../models/user.model.js'

export const getUsers = async (req, res, next) => {
  try {
    const users = await User.find().select('-password');

    res.status(200).json({ success: true, data: users });
  } catch (error) {
    next(error);
  }
}

export const getUser = async (req, res, next) => {
  try {
    const user = await User.findById(req.params.id).select('-password');

    if (!user) {
      const error = new Error('User not found');
      error.statusCode = 404;
      throw error;
    }

    res.status(200).json({ success: true, data: user });
  } catch (error) {
    next(error);
  }
}

export const updateUser = async (req, res, next) => {
  try {
    // Only allow users to update their own profile
    if (req.user.id !== req.params.id) {
      const error = new Error('You can only update your own profile');
      error.statusCode = 403;
      throw error;
    }

    const allowedUpdates = ['name', 'email'];
    const updates = {};
    for (const key of allowedUpdates) {
      if (req.body[key] !== undefined) {
        updates[key] = req.body[key];
      }
    }

    // If password change is requested, hash the new password
    if (req.body.password) {
      const salt = await bcrypt.genSalt(10);
      updates.password = await bcrypt.hash(req.body.password, salt);
    }

    const user = await User.findByIdAndUpdate(
      req.params.id,
      updates,
      { new: true, runValidators: true }
    ).select('-password');

    if (!user) {
      const error = new Error('User not found');
      error.statusCode = 404;
      throw error;
    }

    res.status(200).json({ success: true, message: 'User updated successfully', data: user });
  } catch (error) {
    next(error);
  }
}

export const deleteUser = async (req, res, next) => {
  const session = await mongoose.startSession();
  session.startTransaction();

  try {
    // Only allow users to delete their own account
    if (req.user.id !== req.params.id) {
      const error = new Error('You can only delete your own account');
      error.statusCode = 403;
      throw error;
    }

    const user = await User.findByIdAndDelete(req.params.id, { session });

    if (!user) {
      const error = new Error('User not found');
      error.statusCode = 404;
      throw error;
    }

    // Also delete all user's subscriptions
    const Subscription = mongoose.model('Subscription');
    await Subscription.deleteMany({ user: req.params.id }, { session });

    await session.commitTransaction();
    session.endSession();

    res.status(200).json({ success: true, message: 'User and associated subscriptions deleted successfully' });
  } catch (error) {
    await session.abortTransaction();
    session.endSession();
    next(error);
  }
}