defmodule MicelioWeb.LegalInfo do
  @moduledoc false

  @operator_name "Pedro Piñera Buendía"
  @address "Jessnerstrasse 27a, 10247 Berlin, Germany"

  @support_email "support@micelio.dev"
  @privacy_email "privacy@micelio.dev"
  @legal_email "legal@micelio.dev"
  @tax_id "10273546942"

  def operator_name, do: @operator_name
  def address_one_line, do: @address

  def support_email, do: @support_email
  def privacy_email, do: @privacy_email
  def legal_email, do: @legal_email
  def tax_id, do: @tax_id

  def berlin_supervisory_authority do
    %{
      name: "Berliner Beauftragte für Datenschutz und Informationsfreiheit",
      url: "https://www.datenschutz-berlin.de/"
    }
  end

  def hosting_provider do
    %{name: "Hetzner Online GmbH", url: "https://www.hetzner.com/"}
  end

  def merchant_of_record do
    %{name: "Polar (Merchant of Record)", url: "https://polar.sh/"}
  end

  def email_provider do
    %{name: "Plunk", url: "https://www.useplunk.com/"}
  end
end
