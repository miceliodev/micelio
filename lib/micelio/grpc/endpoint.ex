defmodule Micelio.GRPC.Endpoint do
  use GRPC.Endpoint

  intercept(Micelio.GRPC.ErrorInterceptor)
  intercept(Micelio.GRPC.RateLimitInterceptor, limit: 100, window_ms: 60_000)

  run(Micelio.GRPC.Auth.V1.DeviceAuthService.Server)
  run(Micelio.GRPC.Organizations.V1.OrganizationService.Server)
  run(Micelio.GRPC.Repositories.V1.ProjectService.Server)
  run(Micelio.GRPC.Content.V1.ContentService.Server)
  run(Micelio.GRPC.Sessions.V1.SessionService.Server)
end
