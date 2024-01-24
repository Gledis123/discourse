import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { inject as service } from "@ember/service";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { isTesting } from "discourse-common/config/environment";
import ItsATrap from "@discourse/itsatrap";
import { waitForPromise } from "@ember/test-waiters";
import { DEBUG } from "@glimmer/env";
import SwipeEvents from "discourse/lib/swipe-events";
import { classNameBindings } from "@ember-decorators/component";
import { schedule } from "@ember/runloop";
import { bind } from "discourse-common/utils/decorators";
import GlimmerHeader from "./glimmer-header";

let _menuPanelClassesToForceDropdown = [];
const PANEL_WIDTH = 340;

@classNameBindings("site.mobileView::drop-down-mode")
export default class GlimmerSiteHeader extends Component {
  @service appEvents;
  @service currentUser;
  @service site;
  @service docking;

  @tracked _dockedHeader = false;
  @tracked _topic = null;
  @tracked _swipeMenuOrigin = null;
  @tracked headerWrap = null;
  @tracked _swipeEvents = null;
  @tracked _applicationElement = null;
  @tracked _resizeObserver = null;
  @tracked _docAt = null;

  header = null;

  get dropDownHeaderEnabled() {
    return !this.sidebarEnabled || this.site.narrowDesktopView;
  }

  get leftMenuClass() {
    if (document.querySelector("html").classList["direction"] === "rtl") {
      return "user-menu";
    } else {
      return "hamburger-panel";
    }
  }

  constructor() {
    super(...arguments);
    this.docking.initializeDockCheck(this.dockCheck);

    if (this.currentUser.staff) {
      document.body.classList.add("staff");
    }
  }

  @bind
  updateHeaderOffset() {
    // Safari likes overscolling the page (on both iOS and macOS).
    // This shows up as a negative value in window.scrollY.
    // We can use this to offset the headerWrap's top offset to avoid
    // jitteriness and bad positioning.
    const windowOverscroll = Math.min(0, window.scrollY);

    // The headerWrap's top offset can also be a negative value on Safari,
    // because of the changing height of the viewport (due to the URL bar).
    // For our use case, it's best to ensure this is clamped to 0.
    const headerWrapTop = Math.max(
      0,
      Math.floor(this._headerWrap.getBoundingClientRect().top)
    );
    let offsetTop = headerWrapTop + windowOverscroll;

    if (DEBUG && isTesting()) {
      offsetTop -= document
        .getElementById("ember-testing-container")
        .getBoundingClientRect().top;

      offsetTop -= 1; // For 1px border on testing container
    }

    const documentStyle = document.documentElement.style;

    const currentValue =
      parseInt(documentStyle.getPropertyValue("--header-offset"), 10) || 0;
    const newValue = this._headerWrap.offsetHeight + offsetTop;

    if (currentValue !== newValue) {
      documentStyle.setProperty("--header-offset", `${newValue}px`);
    }
  }

  @bind
  _onScroll() {
    schedule("afterRender", this.updateHeaderOffset);
  }

  @action
  setupHeader() {
    this.appEvents.on("header:show-topic", this, this._setTopic);
    this.appEvents.on("header:hide-topic", this, this._setTopic);
    this.appEvents.on("user-menu:rendered", this, this._animateMenu);
    // this.appEvents.on("dom:clean", this, this._cleanDom);
    if (this.dropDownHeaderEnabled) {
      this.appEvents.on(
        "sidebar-hamburger-dropdown:rendered",
        this,
        this._animateMenu
      );
    }

    // this.dispatch("notifications:changed", "user-notifications");
    // this.dispatch("header:keyboard-trigger", "header");
    // this.dispatch("user-menu:navigation", "user-menu");

    // if (this.currentUser) {
    //   this.currentUser.on("status-changed", this, "queueRerender");
    // }
    // this.appEvents.on("site-header:force-refresh", this, "queueRerender");

    this._headerWrap = document.querySelector(".d-header-wrap");
    if (this._headerWrap) {
      schedule("afterRender", () => {
        this.header = this._headerWrap.querySelector("header.d-header");
        this.updateHeaderOffset();
        document.documentElement.style.setProperty(
          "--header-top",
          `${this.header.offsetTop}px`
        );
      });

      window.addEventListener("scroll", this._onScroll, {
        passive: true,
      });

      this._itsatrap = new ItsATrap(this.header);
      const dirs = ["up", "down"];
      this._itsatrap.bind(dirs, (e) => this._handleArrowKeysNav(e));

      if ("ResizeObserver" in window) {
        this._resizeObserver = new ResizeObserver((entries) => {
          for (let entry of entries) {
            if (entry.contentRect) {
              const headerTop = this.header?.offsetTop;
              document.documentElement.style.setProperty(
                "--header-top",
                `${headerTop}px`
              );
              this.updateHeaderOffset();
            }
          }
        });

        this._resizeObserver.observe(this._headerWrap);
      }

      this._swipeEvents = new SwipeEvents(this._headerWrap);
      if (this.site.mobileView) {
        this._swipeEvents.addTouchListeners();
        this._headerWrap.addEventListener("swipestart", this.onSwipeStart);
        this._headerWrap.addEventListener("swipeend", this.onSwipeEnd);
        this._headerWrap.addEventListener("swipecancel", this.onSwipeCancel);
        this._headerWrap.addEventListener("swipe", this.onSwipe);
      }
    }
  }

  @action
  _setTopic(topic) {
    // this.eventDispatched("dom:clean", "header");
    this._topic = topic;
  }

  _handleArrowKeysNav(event) {
    const activeTab = document.querySelector(
      ".menu-tabs-container .btn.active"
    );
    if (activeTab) {
      let activeTabNumber = Number(
        document.activeElement.dataset.tabNumber || activeTab.dataset.tabNumber
      );
      const maxTabNumber =
        document.querySelectorAll(".menu-tabs-container .btn").length - 1;
      const isNext = event.key === "ArrowDown";
      let nextTab = isNext ? activeTabNumber + 1 : activeTabNumber - 1;
      if (isNext && nextTab > maxTabNumber) {
        nextTab = 0;
      }
      if (!isNext && nextTab < 0) {
        nextTab = maxTabNumber;
      }
      event.preventDefault();
      document
        .querySelector(
          `.menu-tabs-container .btn[data-tab-number='${nextTab}']`
        )
        .focus();
    }
  }

  // _cleanDom() {
  //   if (document.querySelector(".menu-panel")) {
  //     this.eventDispatched("dom:clean", "header");
  //   }
  // }

  _animateMenu() {
    const menuPanels = document.querySelectorAll(".menu-panel");
    let animate;

    if (menuPanels.length === 0) {
      animate = this.site.mobileView || this.site.narrowDesktopView;
      return;
    }

    let viewMode =
      this.site.mobileView || this.site.narrowDesktopView
        ? "slide-in"
        : "drop-down";

    menuPanels.forEach((panel) => {
      if (menuPanelContainsClass(panel)) {
        viewMode = "drop-down";
        animate = false;
      }

      const headerCloak = document.querySelector(".header-cloak");

      panel.classList.remove("drop-down");
      panel.classList.remove("slide-in");
      panel.classList.add(viewMode);

      if (animate) {
        let animationFinished = null;
        let finalPosition = PANEL_WIDTH;
        this._swipeMenuOrigin = "right";
        if (
          (this.site.mobileView || this.site.narrowDesktopView) &&
          panel.parentElement.classList.contains(this.leftMenuClass)
        ) {
          this._swipeMenuOrigin = "left";
          finalPosition = -PANEL_WIDTH;
        }
        animationFinished = panel.animate(
          [{ transform: `translate3d(${finalPosition}px, 0, 0)` }],
          {
            fill: "forwards",
          }
        ).finished;

        if (isTesting()) {
          waitForPromise(animationFinished);
        }

        headerCloak.animate([{ opacity: 0 }], { fill: "forwards" });
        headerCloak.style.display = "block";

        animationFinished.then(() => {
          if (isTesting()) {
            this._animateOpening(panel);
          } else {
            discourseLater(() => this._animateOpening(panel));
          }
        });
      }

      animate = false;
    });
  }

  dockCheck() {
    if (this._docAt === null) {
      if (!this.header) {
        return;
      }
      this._docAt = this.header.offsetTop;
    }

    const main = (this._applicationElement ??=
      document.querySelector(".ember-application"));
    const offsetTop = main ? main.offsetTop : 0;
    const offset = window.pageYOffset - offsetTop;
    if (offset >= this._docAt) {
      if (!this._dockedHeader) {
        document.body.classList.add("docked");
        this._dockedHeader = true;
      }
    } else {
      if (this._dockedHeader) {
        document.body.classList.remove("docked");
        this._dockedHeader = false;
      }
    }
  }

  willDestroy() {
    super.willDestroy(...arguments);
    this.appEvents.off("header:show-topic", this, this._setTopic);
    this.appEvents.off("header:hide-topic", this, this._setTopic);
    // this.appEvents.off("dom:clean", this, this._cleanDom);
    this.appEvents.off("user-menu:rendered", this, this._animateMenu);

    if (this.dropDownHeaderEnabled) {
      this.appEvents.off(
        "sidebar-hamburger-dropdown:rendered",
        this,
        this._animateMenu
      );
    }

    // this.currentUser?.off?.("status-changed", this, "queueRerender");

    this._itsatrap?.destroy();
    this._itsatrap = null;

    window.removeEventListener("scroll", this._onScroll);
    this._resizeObserver?.disconnect();
    // this.appEvents.off("site-header:force-refresh", this, "queueRerender");
    if (this.site.mobileView) {
      this._headerWrap.removeEventListener("swipestart", this.onSwipeStart);
      this._headerWrap.removeEventListener("swipeend", this.onSwipeEnd);
      this._headerWrap.removeEventListener("swipecancel", this.onSwipeCancel);
      this._headerWrap.removeEventListener("swipe", this.onSwipe);
      this._swipeEvents.removeTouchListeners();
    }
  }

  <template>
    <div class="d-header-wrap" {{didInsert this.setupHeader}}>
      <GlimmerHeader
        @canSignUp={{@canSignUp}}
        @showSidebar={{@showSidebar}}
        @sidebarEnabled={{@sidebarEnabled}}
        @navigationMenuQueryParamOverride={{@navigationMenuQueryParamOverride}}
        @toggleSidebar={{@toggleSidebar}}
        @topic={{this._topic}}
        @showCreateAccount={{@showCreateAccount}}
        @showLogin={{@showLogin}}
      />
    </div>
  </template>
}

function menuPanelContainsClass(menuPanel) {
  if (!_menuPanelClassesToForceDropdown) {
    return false;
  }

  for (let className of _menuPanelClassesToForceDropdown) {
    if (menuPanel.classList.contains(className)) {
      return true;
    }
  }

  return false;
}

export function forceDropdownForMenuPanels(classNames) {
  if (typeof classNames === "string") {
    classNames = [classNames];
  }
  return _menuPanelClassesToForceDropdown.push(...classNames);
}
