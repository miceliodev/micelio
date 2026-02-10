ExUnit.start()

# Mimic copies must be done globally for async tests to work properly.
# When tests run in parallel, only the global owner process can call
# expect/stub on mocked modules.
#
# Note: Do NOT mock OTP primitives like Task.Supervisor - use dependency
# injection or async: false options instead.
Mimic.copy(Micelio.Accounts)
Mimic.copy(Micelio.Repositories)
Mimic.copy(Micelio.Mic.Landing)
Mimic.copy(Micelio.Notifications)
Mimic.copy(Micelio.Webhooks)
Mimic.copy(Req)

Ecto.Adapters.SQL.Sandbox.mode(Micelio.Repo, :manual)
