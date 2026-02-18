export type RepositoryItem = {
  id: string;
  name: string;
  handle: string;
  description?: string | null;
  visibility: "public" | "private";
  star_count: number;
  updated_at?: string | null;
  organization: {
    id: string;
    handle: string;
    name: string;
  };
};

export type PlanItem = {
  id: string;
  number: number;
  title: string;
  description?: string | null;
  status: "open" | "closed";
  sandbox_provider?: string | null;
  sandbox_status?: "none" | "provisioning" | "running" | "stopping" | "stopped" | "error" | null;
  sandbox_workspace_id?: string | null;
  sandbox_preview_url?: string | null;
  sandbox_dashboard_url?: string | null;
  forge_branch_name?: string | null;
  forge_pr_provider?: string | null;
  forge_pr_number?: number | null;
  forge_pr_url?: string | null;
  forge_pr_state?: string | null;
  forge_pr_draft?: boolean;
  user?: {
    id: string;
    email: string;
  } | null;
};

export type PaginationResult<T> = {
  data: T[];
};

const API_BASE_URL = process.env.EXPO_PUBLIC_API_BASE_URL || "https://micelio.dev";

async function apiFetch<T>(token: string, path: string, options: RequestInit = {}): Promise<T> {
  const response = await fetch(`${API_BASE_URL}${path}`, {
    ...options,
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      ...(options.headers || {})
    }
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(text || `Request failed with status ${response.status}`);
  }

  return response.json() as Promise<T>;
}

export async function listRepositories(token: string): Promise<RepositoryItem[]> {
  const result = await apiFetch<PaginationResult<RepositoryItem>>(token, "/api/mobile/repositories");
  return result.data;
}

export async function listPlans(
  token: string,
  orgHandle: string,
  repoHandle: string
): Promise<PlanItem[]> {
  const result = await apiFetch<PaginationResult<PlanItem>>(
    token,
    `/api/orgs/${encodeURIComponent(orgHandle)}/repositories/${encodeURIComponent(repoHandle)}/plans`
  );

  return result.data;
}

export async function createPlan(
  token: string,
  orgHandle: string,
  repoHandle: string,
  title: string,
  description: string
): Promise<PlanItem> {
  const result = await apiFetch<{ data: PlanItem }>(
    token,
    `/api/orgs/${encodeURIComponent(orgHandle)}/repositories/${encodeURIComponent(repoHandle)}/plans`,
    {
      method: "POST",
      body: JSON.stringify({ title, description })
    }
  );

  return result.data;
}

export async function startPlanSession(
  token: string,
  orgHandle: string,
  repoHandle: string,
  planNumber: number
): Promise<PlanItem> {
  const result = await apiFetch<{ data: PlanItem }>(
    token,
    `/api/orgs/${encodeURIComponent(orgHandle)}/repositories/${encodeURIComponent(repoHandle)}/plans/${planNumber}/session/start`,
    {
      method: "POST"
    }
  );

  return result.data;
}
