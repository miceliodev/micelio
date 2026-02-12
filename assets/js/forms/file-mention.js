const MAX_SUGGESTIONS = 10;

// Properties to copy from textarea to mirror for caret position calculation
const MIRROR_PROPERTIES = [
  "direction",
  "boxSizing",
  "width",
  "height",
  "overflowX",
  "overflowY",
  "borderTopWidth",
  "borderRightWidth",
  "borderBottomWidth",
  "borderLeftWidth",
  "paddingTop",
  "paddingRight",
  "paddingBottom",
  "paddingLeft",
  "fontStyle",
  "fontVariant",
  "fontWeight",
  "fontStretch",
  "fontSize",
  "fontSizeAdjust",
  "lineHeight",
  "fontFamily",
  "textAlign",
  "textTransform",
  "textIndent",
  "textDecoration",
  "letterSpacing",
  "wordSpacing",
  "tabSize",
  "MozTabSize",
  "whiteSpace",
  "wordWrap",
];

function getCaretCoordinates(textarea, position) {
  const mirror = document.createElement("div");
  mirror.style.position = "absolute";
  mirror.style.visibility = "hidden";
  mirror.style.overflow = "hidden";
  mirror.style.height = "0";
  mirror.style.top = "0";
  mirror.style.left = "0";

  const computed = window.getComputedStyle(textarea);
  for (const prop of MIRROR_PROPERTIES) {
    mirror.style[prop] = computed[prop];
  }

  mirror.style.overflowY = "hidden";
  mirror.style.height = "auto";
  mirror.style.width = computed.width;

  const textBefore = textarea.value.substring(0, position);
  mirror.textContent = textBefore;

  const span = document.createElement("span");
  span.textContent = textarea.value.substring(position) || ".";
  mirror.appendChild(span);

  document.body.appendChild(mirror);

  const coordinates = {
    top: span.offsetTop - textarea.scrollTop,
    left: span.offsetLeft,
  };

  document.body.removeChild(mirror);
  return coordinates;
}

export const FileMention = {
  mounted() {
    this.textarea = this.el.querySelector("textarea");
    if (!this.textarea) return;

    try {
      this.filePaths = JSON.parse(this.el.dataset.filePaths || "[]");
    } catch (_e) {
      this.filePaths = [];
    }

    this.isOpen = false;
    this.selectedIndex = 0;
    this.mentionStart = -1;
    this.currentItems = [];

    this.dropdown = document.createElement("div");
    this.dropdown.className = "file-mention-dropdown";
    this.dropdown.setAttribute("role", "listbox");
    this.dropdown.hidden = true;
    document.body.appendChild(this.dropdown);

    this.onInput = this.handleInput.bind(this);
    this.onKeyDown = this.handleKeyDown.bind(this);
    this.onBlur = this.handleBlur.bind(this);
    this.onDropdownMouseDown = this.handleDropdownMouseDown.bind(this);

    this.textarea.addEventListener("input", this.onInput);
    this.textarea.addEventListener("keydown", this.onKeyDown);
    this.textarea.addEventListener("blur", this.onBlur);
    this.dropdown.addEventListener("mousedown", this.onDropdownMouseDown);
  },

  destroyed() {
    if (this.textarea) {
      this.textarea.removeEventListener("input", this.onInput);
      this.textarea.removeEventListener("keydown", this.onKeyDown);
      this.textarea.removeEventListener("blur", this.onBlur);
    }
    if (this.dropdown) {
      this.dropdown.removeEventListener("mousedown", this.onDropdownMouseDown);
      this.dropdown.remove();
    }
  },

  handleInput() {
    const cursorPos = this.textarea.selectionStart;
    const text = this.textarea.value;
    const textBeforeCursor = text.substring(0, cursorPos);
    const atIndex = textBeforeCursor.lastIndexOf("@");

    if (atIndex === -1) {
      this.close();
      return;
    }

    if (atIndex > 0 && /\w/.test(text[atIndex - 1])) {
      this.close();
      return;
    }

    const query = text.substring(atIndex + 1, cursorPos);

    if (/\s/.test(query)) {
      this.close();
      return;
    }

    this.mentionStart = atIndex;
    this.showSuggestions(query);
  },

  showSuggestions(query) {
    if (this.filePaths.length === 0) {
      this.close();
      return;
    }

    const lowerQuery = query.toLowerCase();
    const filtered = this.filePaths
      .filter((path) => path.toLowerCase().includes(lowerQuery))
      .slice(0, MAX_SUGGESTIONS);

    if (filtered.length === 0) {
      this.close();
      return;
    }

    this.isOpen = true;
    this.selectedIndex = 0;
    this.currentItems = filtered;
    this.renderDropdown();
    this.dropdown.hidden = false;
    this.positionDropdown();
  },

  renderDropdown() {
    this.dropdown.innerHTML = "";

    this.currentItems.forEach((path, index) => {
      const item = document.createElement("div");
      item.className = "file-mention-item";
      if (index === this.selectedIndex) {
        item.classList.add("file-mention-item--active");
        item.setAttribute("aria-selected", "true");
      }
      item.setAttribute("role", "option");
      item.dataset.index = index;
      item.dataset.path = path;

      const icon = document.createElement("span");
      icon.className = "file-mention-icon";
      icon.innerHTML =
        '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>';
      item.appendChild(icon);

      const pathEl = document.createElement("span");
      pathEl.className = "file-mention-path";
      pathEl.textContent = path;
      item.appendChild(pathEl);

      this.dropdown.appendChild(item);
    });
  },

  positionDropdown() {
    const coords = getCaretCoordinates(this.textarea, this.mentionStart);
    const computed = window.getComputedStyle(this.textarea);
    const lineHeight = parseInt(computed.lineHeight, 10);
    const paddingTop = parseInt(computed.paddingTop, 10) || 0;
    const paddingLeft = parseInt(computed.paddingLeft, 10) || 0;
    const borderTop = parseInt(computed.borderTopWidth, 10) || 0;
    const borderLeft = parseInt(computed.borderLeftWidth, 10) || 0;

    const rect = this.textarea.getBoundingClientRect();

    // Fixed position: textarea viewport position + border + padding + caret offset + line height
    let top = rect.top + borderTop + paddingTop + coords.top + (lineHeight || 20) + 4;
    let left = rect.left + borderLeft + paddingLeft + coords.left;

    const dropdownWidth = Math.min(this.textarea.offsetWidth, 400);

    // Keep dropdown within viewport
    if (left + dropdownWidth > window.innerWidth - 16) {
      left = Math.max(16, window.innerWidth - dropdownWidth - 16);
    }

    this.dropdown.style.top = top + "px";
    this.dropdown.style.left = left + "px";
    this.dropdown.style.minWidth = "200px";
    this.dropdown.style.maxWidth = dropdownWidth + "px";
  },

  handleKeyDown(event) {
    if (!this.isOpen) return;

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault();
        this.selectedIndex = Math.min(
          this.selectedIndex + 1,
          this.currentItems.length - 1,
        );
        this.renderDropdown();
        break;

      case "ArrowUp":
        event.preventDefault();
        this.selectedIndex = Math.max(this.selectedIndex - 1, 0);
        this.renderDropdown();
        break;

      case "Enter":
        event.preventDefault();
        this.selectItem(this.currentItems[this.selectedIndex]);
        break;

      case "Tab":
        event.preventDefault();
        this.selectItem(this.currentItems[this.selectedIndex]);
        break;

      case "Escape":
        event.preventDefault();
        this.close();
        break;
    }
  },

  selectItem(path) {
    if (!path) return;

    const text = this.textarea.value;
    const before = text.substring(0, this.mentionStart);
    const after = text.substring(this.textarea.selectionStart);
    const insertion = "@" + path + " ";

    this.textarea.value = before + insertion + after;

    const newCursorPos = before.length + insertion.length;
    this.textarea.selectionStart = newCursorPos;
    this.textarea.selectionEnd = newCursorPos;

    this.textarea.dispatchEvent(new Event("input", { bubbles: true }));

    this.close();
    this.textarea.focus();
  },

  handleDropdownMouseDown(event) {
    const item = event.target.closest(".file-mention-item");
    if (item) {
      event.preventDefault();
      this.selectItem(item.dataset.path);
    }
  },

  handleBlur() {
    setTimeout(() => this.close(), 150);
  },

  close() {
    this.isOpen = false;
    this.dropdown.hidden = true;
    this.dropdown.innerHTML = "";
    this.currentItems = [];
    this.selectedIndex = 0;
  },
};
