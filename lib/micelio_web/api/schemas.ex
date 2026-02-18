defmodule MicelioWeb.Api.Schemas do
  @moduledoc """
  OpenAPI schema definitions for the Micelio REST API.
  """

  alias OpenApiSpex.Schema

  defmodule Error do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Error",
      type: :object,
      properties: %{
        error: %Schema{type: :string, description: "Error code"},
        error_description: %Schema{type: :string, description: "Human-readable error message"}
      },
      required: [:error]
    })
  end

  defmodule Repository do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Repository",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        handle: %Schema{type: :string},
        name: %Schema{type: :string},
        description: %Schema{type: :string, nullable: true},
        url: %Schema{type: :string, nullable: true},
        visibility: %Schema{type: :string, enum: ["public", "private"]},
        organization_handle: %Schema{type: :string},
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :handle, :name, :visibility]
    })
  end

  defmodule RepositoryList do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "RepositoryList",
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: Repository}
      },
      required: [:data]
    })
  end

  defmodule CreateRepositoryRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "CreateRepositoryRequest",
      type: :object,
      properties: %{
        handle: %Schema{type: :string, description: "URL-safe identifier"},
        name: %Schema{type: :string, description: "Display name"},
        description: %Schema{type: :string, nullable: true},
        visibility: %Schema{type: :string, enum: ["public", "private"], default: "private"}
      },
      required: [:handle, :name]
    })
  end

  defmodule UpdateRepositoryRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "UpdateRepositoryRequest",
      type: :object,
      properties: %{
        name: %Schema{type: :string},
        description: %Schema{type: :string, nullable: true},
        visibility: %Schema{type: :string, enum: ["public", "private"]}
      }
    })
  end

  defmodule Session do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Session",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        session_id: %Schema{type: :string},
        goal: %Schema{type: :string},
        status: %Schema{type: :string, enum: ["active", "landed", "abandoned"]},
        started_at: %Schema{type: :string, format: :"date-time", nullable: true},
        landed_at: %Schema{type: :string, format: :"date-time", nullable: true},
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :session_id, :goal, :status]
    })
  end

  defmodule SessionList do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SessionList",
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: Session}
      },
      required: [:data]
    })
  end

  defmodule StartSessionRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "StartSessionRequest",
      type: :object,
      properties: %{
        goal: %Schema{type: :string, description: "What you are trying to accomplish"}
      },
      required: [:goal]
    })
  end

  defmodule Organization do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Organization",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        handle: %Schema{type: :string},
        name: %Schema{type: :string},
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :handle, :name]
    })
  end

  defmodule OrganizationList do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "OrganizationList",
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: Organization}
      },
      required: [:data]
    })
  end

  defmodule TreeEntry do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "TreeEntry",
      type: :object,
      properties: %{
        name: %Schema{type: :string},
        type: %Schema{type: :string, enum: ["blob", "tree"]},
        size: %Schema{type: :integer, nullable: true}
      },
      required: [:name, :type]
    })
  end

  defmodule TreeResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "TreeResponse",
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: TreeEntry}
      },
      required: [:data]
    })
  end

  defmodule BlobResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "BlobResponse",
      type: :object,
      properties: %{
        data: %Schema{
          type: :object,
          properties: %{
            content: %Schema{type: :string, description: "File content (base64 for binary)"},
            encoding: %Schema{type: :string, enum: ["utf-8", "base64"]},
            size: %Schema{type: :integer}
          }
        }
      },
      required: [:data]
    })
  end

  defmodule BlameLine do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "BlameLine",
      type: :object,
      properties: %{
        line_number: %Schema{type: :integer},
        text: %Schema{type: :string},
        session_id: %Schema{type: :string, nullable: true},
        author: %Schema{type: :string, nullable: true},
        landed_at: %Schema{type: :string, format: :"date-time", nullable: true}
      }
    })
  end

  defmodule BlameResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "BlameResponse",
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: BlameLine}
      },
      required: [:data]
    })
  end

  defmodule Plan do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Plan",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        number: %Schema{type: :integer},
        title: %Schema{type: :string},
        description: %Schema{type: :string, nullable: true},
        status: %Schema{type: :string, enum: ["open", "closed"]},
        sandbox_provider: %Schema{type: :string, nullable: true},
        sandbox_status: %Schema{
          type: :string,
          nullable: true,
          enum: ["none", "provisioning", "running", "stopping", "stopped", "error"]
        },
        sandbox_workspace_id: %Schema{type: :string, nullable: true},
        sandbox_preview_url: %Schema{type: :string, nullable: true},
        sandbox_dashboard_url: %Schema{type: :string, nullable: true},
        forge_branch_name: %Schema{type: :string, nullable: true},
        forge_pr_provider: %Schema{type: :string, nullable: true, enum: ["github", "gitlab"]},
        forge_pr_number: %Schema{type: :integer, nullable: true},
        forge_pr_url: %Schema{type: :string, nullable: true},
        forge_pr_state: %Schema{
          type: :string,
          nullable: true,
          enum: ["open", "closed", "merged", "draft", "unknown"]
        },
        forge_pr_draft: %Schema{type: :boolean, nullable: true},
        user: %Schema{
          type: :object,
          nullable: true,
          properties: %{
            id: %Schema{type: :string, format: :uuid},
            email: %Schema{type: :string}
          }
        },
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :number, :title, :status]
    })
  end

  defmodule PlanList do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "PlanList",
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: Plan}
      },
      required: [:data]
    })
  end

  defmodule CreatePlanRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "CreatePlanRequest",
      type: :object,
      properties: %{
        title: %Schema{type: :string, description: "Title of the plan"},
        description: %Schema{type: :string, description: "Detailed description", nullable: true}
      },
      required: [:title]
    })
  end

  defmodule UpdatePlanRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "UpdatePlanRequest",
      type: :object,
      properties: %{
        title: %Schema{type: :string},
        description: %Schema{type: :string, nullable: true}
      }
    })
  end
end
