//! Shell activation for automatic workspace watcher management.

use crate::cli::ActivateCommand;
use crate::error::Result;

pub async fn run(cmd: ActivateCommand) -> Result<()> {
    let script = match cmd.shell.as_str() {
        "bash" => bash_script(),
        "zsh" => zsh_script(),
        "fish" => fish_script(),
        _ => unreachable!("clap validates supported shells"),
    };

    print!("{}", script);
    Ok(())
}

fn bash_script() -> &'static str {
    r#"if [[ -z "${_HIF_ACTIVATE_WATCH:-}" ]]; then
  export _HIF_ACTIVATE_WATCH=1

  __hif_watch_refresh() {
    local previous="${HIF_WATCH_WORKSPACE:-}"
    local current=""

    current="$(command hif watch ensure --shell-pid "$$" --print-root 2>/dev/null || true)"

    if [[ -n "$previous" && "$previous" != "$current" ]]; then
      command hif watch leave --workspace-root "$previous" --shell-pid "$$" >/dev/null 2>&1 || true
    fi

    if [[ -n "$current" ]]; then
      export HIF_WATCH_WORKSPACE="$current"
    else
      unset HIF_WATCH_WORKSPACE
    fi
  }

  __hif_watch_cleanup() {
    if [[ -n "${HIF_WATCH_WORKSPACE:-}" ]]; then
      command hif watch leave --workspace-root "$HIF_WATCH_WORKSPACE" --shell-pid "$$" >/dev/null 2>&1 || true
      unset HIF_WATCH_WORKSPACE
    fi
  }

  if [[ -n "${PROMPT_COMMAND:-}" ]]; then
    PROMPT_COMMAND="__hif_watch_refresh;${PROMPT_COMMAND}"
  else
    PROMPT_COMMAND="__hif_watch_refresh"
  fi

  trap '__hif_watch_cleanup' EXIT
fi
"#
}

fn zsh_script() -> &'static str {
    r#"if [[ -z "${_HIF_ACTIVATE_WATCH:-}" ]]; then
  export _HIF_ACTIVATE_WATCH=1

  __hif_watch_refresh() {
    emulate -L zsh
    local previous="${HIF_WATCH_WORKSPACE:-}"
    local current=""

    current="$(command hif watch ensure --shell-pid "$$" --print-root 2>/dev/null || true)"

    if [[ -n "$previous" && "$previous" != "$current" ]]; then
      command hif watch leave --workspace-root "$previous" --shell-pid "$$" >/dev/null 2>&1 || true
    fi

    if [[ -n "$current" ]]; then
      export HIF_WATCH_WORKSPACE="$current"
    else
      unset HIF_WATCH_WORKSPACE
    fi
  }

  __hif_watch_cleanup() {
    emulate -L zsh
    if [[ -n "${HIF_WATCH_WORKSPACE:-}" ]]; then
      command hif watch leave --workspace-root "$HIF_WATCH_WORKSPACE" --shell-pid "$$" >/dev/null 2>&1 || true
      unset HIF_WATCH_WORKSPACE
    fi
  }

  autoload -Uz add-zsh-hook
  add-zsh-hook chpwd __hif_watch_refresh
  add-zsh-hook precmd __hif_watch_refresh
  zshexit_functions+=(__hif_watch_cleanup)
fi
"#
}

fn fish_script() -> &'static str {
    r#"if not set -q _HIF_ACTIVATE_WATCH
    set -gx _HIF_ACTIVATE_WATCH 1

    function __hif_watch_refresh --on-variable PWD --on-event fish_prompt
        set -l previous "$HIF_WATCH_WORKSPACE"
        set -l current (command hif watch ensure --shell-pid "$fish_pid" --print-root 2>/dev/null)

        if test -n "$previous"; and test "$previous" != "$current"
            command hif watch leave --workspace-root "$previous" --shell-pid "$fish_pid" >/dev/null 2>&1
        end

        if test -n "$current"
            set -gx HIF_WATCH_WORKSPACE "$current"
        else
            set -e HIF_WATCH_WORKSPACE
        end
    end

    function __hif_watch_cleanup --on-event fish_exit
        if set -q HIF_WATCH_WORKSPACE
            command hif watch leave --workspace-root "$HIF_WATCH_WORKSPACE" --shell-pid "$fish_pid" >/dev/null 2>&1
            set -e HIF_WATCH_WORKSPACE
        end
    end
end
"#
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn zsh_script_sets_up_hidden_watch_commands() {
        let script = zsh_script();
        assert!(script.contains("hif watch ensure"));
        assert!(script.contains("hif watch leave"));
        assert!(script.contains("add-zsh-hook"));
        assert!(script.contains("_HIF_ACTIVATE_WATCH"));
        assert!(script.contains("HIF_WATCH_WORKSPACE"));
    }
}
