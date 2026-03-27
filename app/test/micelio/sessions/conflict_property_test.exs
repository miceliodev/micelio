defmodule Micelio.Sessions.ConflictPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Micelio.Sessions.Conflict

  describe "build_filter/2 properties" do
    property "added paths always register as possible matches" do
      check all(
              paths <- paths_generator(),
              size <- StreamData.integer(64..2048),
              hash_count <- StreamData.integer(1..5)
            ) do
        filter = Conflict.build_filter(paths, size: size, hash_count: hash_count)

        Enum.each(paths, fn path ->
          assert Conflict.might_conflict?(filter, path)
        end)
      end
    end

    property "bitset length matches the configured size" do
      check all(
              paths <- paths_generator(),
              size <- StreamData.integer(64..2048),
              hash_count <- StreamData.integer(1..5)
            ) do
        filter = Conflict.build_filter(paths, size: size, hash_count: hash_count)
        bitset = Base.decode64!(filter["bits"])

        assert byte_size(bitset) == div(size + 7, 8)
      end
    end
  end

  describe "merge_filters/1 properties" do
    property "merged filter includes all paths from inputs" do
      check all(
              left_paths <- paths_generator(),
              right_paths <- paths_generator(),
              size <- StreamData.integer(64..2048),
              hash_count <- StreamData.integer(1..5)
            ) do
        left = Conflict.build_filter(left_paths, size: size, hash_count: hash_count)
        right = Conflict.build_filter(right_paths, size: size, hash_count: hash_count)

        merged = Conflict.merge_filters([left, right])

        Enum.each(left_paths ++ right_paths, fn path ->
          assert Conflict.might_conflict?(merged, path)
        end)
      end
    end
  end

  defp paths_generator do
    StreamData.list_of(path_generator(), min_length: 1, max_length: 25)
  end

  defp path_generator do
    StreamData.bind(
      StreamData.list_of(segment_generator(), min_length: 1, max_length: 4),
      fn segments ->
        StreamData.map(StreamData.member_of(["ex", "md", "txt", "bin"]), fn ext ->
          Enum.join(segments, "/") <> "." <> ext
        end)
      end
    )
  end

  defp segment_generator do
    StreamData.string([?a..?z, ?0..?9, ?_, ?-], min_length: 1, max_length: 10)
  end
end
