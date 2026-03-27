defmodule MicelioWeb.Browser.LegalHTML do
  @moduledoc """
  This module contains pages rendered by LegalController.

  See the `legal_html` directory for all templates available.
  """
  use MicelioWeb, :html
  use Gettext, backend: MicelioWeb.Gettext

  embed_templates "legal_html/*"

  def toc_for(:privacy) do
    [
      %{level: 2, id: "1-controller", text: "1. Controller"},
      %{level: 2, id: "2-data-protection-contact", text: "2. Data protection contact"},
      %{level: 2, id: "3-scope", text: "3. Scope"},
      %{level: 2, id: "4-categories-of-personal-data", text: "4. Categories of personal data"},
      %{level: 2, id: "5-purposes-and-legal-bases", text: "5. Purposes and legal bases"},
      %{level: 2, id: "6-recipients-and-processors", text: "6. Recipients and processors"},
      %{level: 2, id: "7-international-transfers", text: "7. International transfers"},
      %{level: 2, id: "8-retention", text: "8. Retention"},
      %{level: 2, id: "9-your-rights", text: "9. Your rights"},
      %{level: 2, id: "10-supervisory-authority", text: "10. Supervisory authority"},
      %{
        level: 2,
        id: "11-cookies-and-similar-technologies",
        text: "11. Cookies and similar technologies"
      },
      %{level: 2, id: "12-changes", text: "12. Changes"}
    ]
  end

  def toc_for(:terms) do
    [
      %{level: 2, id: "1-provider", text: "1. Provider"},
      %{level: 2, id: "2-about-the-service", text: "2. About the service"},
      %{level: 2, id: "3-accounts", text: "3. Accounts"},
      %{level: 2, id: "4-pricing", text: "4. Pricing"},
      %{level: 2, id: "5-acceptable-use", text: "5. Acceptable use"},
      %{
        level: 2,
        id: "6-content-and-intellectual-property",
        text: "6. Content and intellectual property"
      },
      %{level: 2, id: "7-availability-and-changes", text: "7. Availability and changes"},
      %{level: 2, id: "8-termination", text: "8. Termination"},
      %{level: 2, id: "9-warranty-and-liability", text: "9. Warranty and liability"},
      %{
        level: 2,
        id: "10-governing-law-and-jurisdiction",
        text: "10. Governing law and jurisdiction"
      },
      %{level: 2, id: "11-privacy", text: "11. Privacy"},
      %{level: 2, id: "12-changes-to-these-terms", text: "12. Changes to these terms"}
    ]
  end

  def toc_for(:cookies) do
    [
      %{level: 2, id: "1-what-are-cookies", text: "1. What are cookies?"},
      %{level: 2, id: "2-legal-framework-germanyeu", text: "2. Legal framework (Germany/EU)"},
      %{level: 2, id: "3-cookies-we-use", text: "3. Cookies we use"},
      %{level: 2, id: "4-managing-cookies", text: "4. Managing cookies"},
      %{level: 2, id: "5-contact", text: "5. Contact"}
    ]
  end

  def toc_for(:impressum) do
    [
      %{level: 2, id: "provider", text: "Provider"},
      %{level: 2, id: "register-information", text: "Register information"},
      %{level: 2, id: "responsible-for-content", text: "Responsible for content"},
      %{level: 2, id: "dispute-resolution", text: "Dispute resolution"}
    ]
  end
end
