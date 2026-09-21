const sgMail = require('@sendgrid/mail');

const apiKey = process.env.SENDGRID_API_KEY;
const fromEmail = process.env.SENDGRID_FROM_EMAIL;
const configured = !!(apiKey && fromEmail);

if (configured) {
  sgMail.setApiKey(apiKey);
} else {
  console.warn(
    'SENDGRID_API_KEY / SENDGRID_FROM_EMAIL not set — verification emails will be logged to the ' +
      'console instead of actually sent. Set both env vars to enable real delivery.'
  );
}

// Sends a verification email, or logs the code to the console if SendGrid
// isn't configured (local dev default — lets registration/verification be
// tested end to end without a real email account). Never throws on a
// missing config; only throws if SendGrid itself rejects a real send, so
// the caller can decide how to surface that to the registering user.
async function sendVerificationEmail(toEmail, code) {
  if (!configured) {
    console.log(`[email:dev-mode] Verification code for ${toEmail}: ${code}`);
    return { delivered: false, reason: 'not_configured' };
  }

  await sgMail.send({
    to: toEmail,
    from: fromEmail,
    subject: 'Verify your email — Protected Viewer',
    text: `Your verification code is: ${code}\n\nThis code expires in 30 minutes.`,
    html: `<p>Your verification code is:</p><p style="font-size:28px;font-weight:bold;letter-spacing:4px;">${code}</p><p>This code expires in 30 minutes.</p>`,
  });
  return { delivered: true };
}

module.exports = { sendVerificationEmail, isEmailConfigured: () => configured };
