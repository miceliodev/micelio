defmodule Micelio.Storage.S3Test do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Micelio.Storage.S3

  setup do
    config = [
      backend: :s3,
      s3_bucket: "test-bucket",
      s3_region: "us-east-1",
      s3_access_key_id: "test-key-id",
      s3_secret_access_key: "test-secret-key",
      s3_endpoint: "https://s3.us-east-1.amazonaws.com",
      req_options: [plug: {Req.Test, Micelio.Storage.S3Test}, retry: false]
    ]

    {:ok, config: config}
  end

  describe "put/2" do
    test "successfully stores content in S3", %{config: config} do
      content = "test content"
      key = "sessions/test123/file.txt"

      Req.Test.stub(Micelio.Storage.S3Test, fn conn ->
        assert conn.method == "PUT"
        assert conn.request_path =~ key
        Plug.Conn.send_resp(conn, 200, "")
      end)

      assert {:ok, ^key} = S3.put(key, content, config: config)
    end

    test "returns error on S3 failure", %{config: config} do
      Req.Test.stub(Micelio.Storage.S3Test, fn conn ->
        Plug.Conn.send_resp(conn, 403, "Access Denied")
      end)

      content = "test content"
      key = "sessions/test123/file.txt"

      capture_log(fn ->
        assert {:error, {:s3_error, 403, "Access Denied"}} =
                 S3.put(key, content, config: config)
      end)
    end

    test "returns error on network failure", %{config: config} do
      Req.Test.stub(Micelio.Storage.S3Test, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      content = "test content"
      key = "sessions/test123/file.txt"

      capture_log(fn ->
        assert {:error, %Req.TransportError{reason: :econnrefused}} =
                 S3.put(key, content, config: config)
      end)
    end

    test "handles special characters in keys", %{config: config} do
      content = "test"
      key = "sessions/test 123/file (1).txt"

      Req.Test.stub(Micelio.Storage.S3Test, fn conn ->
        # Verify URL encoding
        assert conn.request_path =~ "sessions/test%20123/file%20%281%29.txt"
        Plug.Conn.send_resp(conn, 200, "")
      end)

      assert {:ok, ^key} = S3.put(key, content, config: config)
    end
  end

  describe "get/1" do
    test "successfully retrieves content from S3", %{config: config} do
      key = "sessions/test123/file.txt"
      content = "stored content"

      Req.Test.stub(Micelio.Storage.S3Test, fn conn ->
        assert conn.method == "GET"
        Plug.Conn.send_resp(conn, 200, content)
      end)

      assert {:ok, ^content} = S3.get(key, config: config)
    end

    test "returns :not_found when object doesn't exist", %{config: config} do
      Req.Test.stub(Micelio.Storage.S3Test, fn conn ->
        Plug.Conn.send_resp(conn, 404, "")
      end)

      key = "sessions/nonexistent/file.txt"

      assert {:error, :not_found} = S3.get(key, config: config)
    end

    test "returns error on S3 failure", %{config: config} do
      Req.Test.stub(Micelio.Storage.S3Test, fn conn ->
        Plug.Conn.send_resp(conn, 500, "Internal Server Error")
      end)

      key = "sessions/test123/file.txt"

      capture_log(fn ->
        assert {:error, {:s3_error, 500, "Internal Server Error"}} =
                 S3.get(key, config: config)
      end)
    end
  end

  describe "delete/1" do
    test "successfully deletes object from S3", %{config: config} do
      Req.Test.stub(Micelio.Storage.S3Test, fn conn ->
        assert conn.method == "DELETE"
        Plug.Conn.send_resp(conn, 204, "")
      end)

      key = "sessions/test123/file.txt"

      assert {:ok, ^key} = S3.delete(key, config: config)
    end

    test "returns success even when object doesn't exist (idempotent)", %{config: config} do
      Req.Test.stub(Micelio.Storage.S3Test, fn conn ->
        Plug.Conn.send_resp(conn, 404, "")
      end)

      key = "sessions/nonexistent/file.txt"

      assert {:ok, ^key} = S3.delete(key, config: config)
    end

    test "returns error on S3 failure", %{config: config} do
      Req.Test.stub(Micelio.Storage.S3Test, fn conn ->
        Plug.Conn.send_resp(conn, 403, "Access Denied")
      end)

      key = "sessions/test123/file.txt"

      capture_log(fn ->
        assert {:error, {:s3_error, 403, "Access Denied"}} =
                 S3.delete(key, config: config)
      end)
    end
  end

  describe "exists?/1" do
    test "returns true when object exists", %{config: config} do
      Req.Test.stub(Micelio.Storage.S3Test, fn conn ->
        assert conn.method == "HEAD"
        Plug.Conn.send_resp(conn, 200, "")
      end)

      key = "sessions/test123/file.txt"

      assert S3.exists?(key, config: config) == true
    end

    test "returns false when object doesn't exist", %{config: config} do
      Req.Test.stub(Micelio.Storage.S3Test, fn conn ->
        Plug.Conn.send_resp(conn, 404, "")
      end)

      key = "sessions/nonexistent/file.txt"

      assert S3.exists?(key, config: config) == false
    end

    test "returns false on S3 errors", %{config: config} do
      Req.Test.stub(Micelio.Storage.S3Test, fn conn ->
        Plug.Conn.send_resp(conn, 500, "")
      end)

      key = "sessions/test123/file.txt"

      capture_log(fn ->
        assert S3.exists?(key, config: config) == false
      end)
    end

    test "returns false on network errors", %{config: config} do
      Req.Test.stub(Micelio.Storage.S3Test, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      key = "sessions/test123/file.txt"

      capture_log(fn ->
        assert S3.exists?(key, config: config) == false
      end)
    end
  end

  describe "list/1" do
    test "successfully lists objects with prefix", %{config: config} do
      prefix = "sessions/test123/"

      xml_response = """
      <?xml version="1.0" encoding="UTF-8"?>
      <ListBucketResult>
        <Name>test-bucket</Name>
        <Prefix>#{prefix}</Prefix>
        <KeyCount>2</KeyCount>
        <MaxKeys>1000</MaxKeys>
        <IsTruncated>false</IsTruncated>
        <Contents>
          <Key>#{prefix}file1.txt</Key>
        </Contents>
        <Contents>
          <Key>#{prefix}file2.txt</Key>
        </Contents>
      </ListBucketResult>
      """

      Req.Test.stub(Micelio.Storage.S3Test, fn conn ->
        assert conn.method == "GET"
        assert conn.query_string =~ "list-type=2"
        assert conn.query_string =~ "prefix="
        Plug.Conn.send_resp(conn, 200, xml_response)
      end)

      assert {:ok, keys} = S3.list(prefix, config: config)

      assert length(keys) == 2
      assert "#{prefix}file1.txt" in keys
      assert "#{prefix}file2.txt" in keys
    end

    test "handles empty list results", %{config: config} do
      prefix = "sessions/empty/"

      xml_response = """
      <?xml version="1.0" encoding="UTF-8"?>
      <ListBucketResult>
        <Name>test-bucket</Name>
        <Prefix>#{prefix}</Prefix>
        <KeyCount>0</KeyCount>
        <IsTruncated>false</IsTruncated>
      </ListBucketResult>
      """

      Req.Test.stub(Micelio.Storage.S3Test, fn conn ->
        Plug.Conn.send_resp(conn, 200, xml_response)
      end)

      assert {:ok, []} = S3.list(prefix, config: config)
    end

    test "returns error on S3 failure", %{config: config} do
      Req.Test.stub(Micelio.Storage.S3Test, fn conn ->
        Plug.Conn.send_resp(conn, 403, "Access Denied")
      end)

      prefix = "sessions/test/"

      capture_log(fn ->
        assert {:error, {:s3_error, 403, "Access Denied"}} =
                 S3.list(prefix, config: config)
      end)
    end
  end

  describe "configuration validation" do
    test "returns error when S3 bucket is not configured" do
      capture_log(fn ->
        assert {:error, :missing_s3_bucket} = S3.put("key", "content", config: [])
      end)
    end

    test "returns error when S3 credentials are not configured" do
      capture_log(fn ->
        assert {:error, :missing_s3_credentials} =
                 S3.put("key", "content", config: [s3_bucket: "test-bucket"])
      end)
    end

    test "uses environment variables for configuration" do
      config = [
        env: %{
          "S3_BUCKET" => "env-bucket",
          "S3_ACCESS_KEY_ID" => "env-key",
          "S3_SECRET_ACCESS_KEY" => "env-secret"
        },
        req_options: [plug: {Req.Test, Micelio.Storage.S3Test}, retry: false]
      ]

      Req.Test.stub(Micelio.Storage.S3Test, fn conn ->
        # Verify the bucket from env is used (virtual host style)
        assert conn.host =~ "env-bucket"
        Plug.Conn.send_resp(conn, 200, "")
      end)

      assert {:ok, _} = S3.put("key", "content", config: config)
    end

    test "prioritizes explicit config over environment variables" do
      config = [
        env: %{"S3_BUCKET" => "env-bucket"},
        s3_bucket: "config-bucket",
        s3_access_key_id: "config-key",
        s3_secret_access_key: "config-secret",
        req_options: [plug: {Req.Test, Micelio.Storage.S3Test}, retry: false]
      ]

      Req.Test.stub(Micelio.Storage.S3Test, fn conn ->
        assert conn.host =~ "config-bucket"
        refute conn.host =~ "env-bucket"
        Plug.Conn.send_resp(conn, 200, "")
      end)

      assert {:ok, _} = S3.put("key", "content", config: config)
    end
  end

  describe "AWS Signature V4 authentication" do
    test "includes required AWS authentication headers", %{config: config} do
      Req.Test.stub(Micelio.Storage.S3Test, fn conn ->
        header_names =
          conn.req_headers
          |> Enum.map(fn {name, _} -> String.downcase(name) end)

        assert "authorization" in header_names
        assert "x-amz-date" in header_names
        assert "x-amz-content-sha256" in header_names
        assert "host" in header_names

        # Verify authorization header format
        {_, auth_header} =
          Enum.find(conn.req_headers, fn {k, _} -> String.downcase(k) == "authorization" end)

        assert auth_header =~ ~r/AWS4-HMAC-SHA256 Credential=/
        assert auth_header =~ ~r/SignedHeaders=/
        assert auth_header =~ ~r/Signature=/

        Plug.Conn.send_resp(conn, 200, "")
      end)

      S3.put("test-key", "test-content", config: config)
    end

    test "includes content SHA256 for PUT requests", %{config: config} do
      content = "test content"
      expected_sha256 = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

      Req.Test.stub(Micelio.Storage.S3Test, fn conn ->
        {_, content_sha256} =
          Enum.find(conn.req_headers, fn {k, _} ->
            String.downcase(k) == "x-amz-content-sha256"
          end)

        assert content_sha256 == expected_sha256
        Plug.Conn.send_resp(conn, 200, "")
      end)

      S3.put("test-key", content, config: config)
    end

    test "uses empty string SHA256 for GET requests", %{config: config} do
      empty_sha256 = :crypto.hash(:sha256, "") |> Base.encode16(case: :lower)

      Req.Test.stub(Micelio.Storage.S3Test, fn conn ->
        {_, content_sha256} =
          Enum.find(conn.req_headers, fn {k, _} ->
            String.downcase(k) == "x-amz-content-sha256"
          end)

        assert content_sha256 == empty_sha256
        Plug.Conn.send_resp(conn, 200, "content")
      end)

      S3.get("test-key", config: config)
    end
  end

  describe "content-addressable storage integration" do
    test "stores and retrieves content by hash-based keys", %{config: config} do
      content = "agent session data"
      # Simulate content-addressable key (SHA256 of content)
      content_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
      key = "artifacts/sha256:#{content_hash}"

      # Expect PUT then GET
      Req.Test.expect(Micelio.Storage.S3Test, fn conn ->
        assert conn.method == "PUT"
        assert conn.request_path =~ content_hash
        Plug.Conn.send_resp(conn, 200, "")
      end)

      Req.Test.expect(Micelio.Storage.S3Test, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path =~ content_hash
        Plug.Conn.send_resp(conn, 200, content)
      end)

      assert {:ok, ^key} = S3.put(key, content, config: config)
      assert {:ok, ^content} = S3.get(key, config: config)
    end

    test "supports session-scoped artifact paths", %{config: config} do
      session_id = "abc123"
      artifact_key = "sessions/#{session_id}/artifacts/build.tar.gz"

      Req.Test.stub(Micelio.Storage.S3Test, fn conn ->
        assert conn.request_path =~ session_id
        assert conn.request_path =~ "artifacts"
        Plug.Conn.send_resp(conn, 200, "")
      end)

      assert {:ok, ^artifact_key} = S3.put(artifact_key, "build data", config: config)
    end
  end
end
