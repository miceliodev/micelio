defmodule Micelio.AgentInfra.CloudPlatformsTest do
  use ExUnit.Case, async: true

  alias Micelio.AgentInfra.CloudPlatforms

  test "all/0 returns evaluated platforms with required fields" do
    platforms = CloudPlatforms.all()
    ids = Enum.map(platforms, & &1.id)

    assert Enum.sort(ids) == Enum.sort([:aws, :gcp, :hetzner, :fly])

    Enum.each(platforms, fn platform ->
      assert is_binary(platform.name) and platform.name != ""
      assert is_binary(platform.summary) and platform.summary != ""
      assert Enum.all?(platform.strengths, &(&1 != ""))
      assert Enum.all?(platform.risks, &(&1 != ""))
      assert Enum.all?(platform.suitability, &(&1 != ""))
      assert Enum.all?(platform.notes, &(&1 != ""))
    end)
  end

  test "find/1 locates platforms by id" do
    assert %{id: :aws} = CloudPlatforms.find(:aws)
    assert %{id: :gcp} = CloudPlatforms.find("gcp")
    assert CloudPlatforms.find("unknown") == nil
  end

  test "recommendations/0 returns a known provider map" do
    %{primary: primary, secondary: secondary, overflow: overflow} =
      CloudPlatforms.recommendations()

    ids = Enum.map(CloudPlatforms.all(), & &1.id)
    assert primary in ids
    assert secondary in ids
    assert overflow in ids
  end
end
