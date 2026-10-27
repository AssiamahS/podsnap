// PODsnap runtime config. Edit these two strings, commit, push — Pages redeploys.
//
// PAY_URL  : your checkout link (Stripe Payment Link, Square, PayPal.me, Lemon Squeezy...).
//            When set, every "Start" button opens it in a new tab.
// CONTACT  : an email address (you@example.com) or a phone number (+15551234567).
//            When PAY_URL is empty, "Start" shows a short request-access form that
//            composes an email (mailto:) or a text (sms:) to this contact.
//
// Leave both empty and the form still works — it just asks the user to copy the request.
window.PODSNAP_CONFIG = {
  PAY_URL: "",
  CONTACT: "",
  PRICE_MONTHLY: 14,
  PRICE_PILOT: 29 // one-time "done-with-you" setup + first 60 days
};
