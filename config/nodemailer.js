import nodemailer from 'nodemailer';

import { EMAIL_USER, EMAIL_PASSWORD } from './env.js'

if (!EMAIL_USER || !EMAIL_PASSWORD) {
  console.warn('Warning: EMAIL_USER or EMAIL_PASSWORD not set. Email sending will fail.');
}

export const accountEmail = EMAIL_USER;

const transporter = nodemailer.createTransport({
  service: 'gmail',
  auth: {
    user: EMAIL_USER,
    pass: EMAIL_PASSWORD
  }
})

export default transporter;