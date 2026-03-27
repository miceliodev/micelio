defmodule Micelio.Encrypted.BinaryTest do
  use ExUnit.Case, async: true

  defmodule TestVault do
    use Cloak.Vault, otp_app: :micelio
  end

  defmodule TestBinary do
    use Cloak.Ecto.Binary, vault: TestVault
  end

  test "supports decryption with previous cipher during key rotation" do
    old_key = <<1::256>>
    new_key = <<2::256>>

    start_supervised!(
      {TestVault,
       json_library: Jason,
       ciphers: [
         default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V0", key: old_key}
       ]}
    )

    assert {:ok, encrypted} = TestBinary.dump("rotating-secret")

    stop_supervised!(TestVault)

    start_supervised!(
      {TestVault,
       json_library: Jason,
       ciphers: [
         default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: new_key},
         previous_1: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V0", key: old_key}
       ]}
    )

    assert {:ok, "rotating-secret"} = TestBinary.load(encrypted)
  end
end
