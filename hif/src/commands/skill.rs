use crate::error::Result;
use crate::output;
use serde::Serialize;

const SKILL_MARKDOWN: &str = include_str!("../../../app/priv/static/SKILL.md");

#[derive(Serialize)]
struct SkillOutput<'a> {
    format: &'static str,
    content: &'a str,
}

pub async fn run() -> Result<()> {
    if output::use_json() {
        output::print_ok(
            "skill",
            SkillOutput {
                format: "markdown",
                content: SKILL_MARKDOWN,
            },
        )
    } else {
        output::ui_text(SKILL_MARKDOWN);
        Ok(())
    }
}
