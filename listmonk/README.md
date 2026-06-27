# listmonk Configuration
# This file is for reference only. In Docker, listmonk is configured via
# environment variables (LISTMONK_* prefix) in docker-compose.yml.
# See: https://listmonk.app/docs/configuration/

# For production (Contabo), configure SES SMTP settings via Doppler:
#
# LISTMONK_smtp__host=email-smtp.us-east-1.amazonaws.com
# LISTMONK_smtp__port=587
# LISTMONK_smtp__username=<ses-smtp-user>
# LISTMONK_smtp__password=<ses-smtp-password>
# LISTMONK_smtp__auth_protocol=login
# LISTMONK_smtp__tls_type=starttls
# LISTMONK_smtp__hello_host=lyrafinai.com
#
# For local development, Mailpit is used instead (see docker-compose.override.yml):
#
# LISTMONK_smtp__host=mailpit
# LISTMONK_smtp__port=1025
# LISTMONK_smtp__auth_protocol=none
# LISTMONK_smtp__tls_type=none

# Initial list design (create via listmonk UI after first login):
# - blog_subscribers
# - product_updates
# - trial_onboarding
# - reengagement
# - creator_referrals
# - internal_test
#
# All first sends must go to internal_test before a public list.

# SES bounce webhook:
# https://newsletter.lyrafinai.com/webhooks/service/ses
