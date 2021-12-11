import Config

# Web push
config :bonfire_notify, Bonfire.Notify.WebPush,
  adapter: Bonfire.Notify.WebPush.HttpAdapter,
  retry_timeout: 1000,
  max_attempts: 5

# Configure browser push notifications
config :web_push_encryption, :vapid_details,
  subject: System.get_env("WEB_PUSH_SUBJECT", "https://bonfire.cafe"),
  public_key: System.get_env("WEB_PUSH_PUBLIC_KEY"),
  private_key: System.get_env("WEB_PUSH_PRIVATE_KEY")
