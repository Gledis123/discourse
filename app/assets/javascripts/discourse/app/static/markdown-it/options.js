import { formatUsername } from "discourse/lib/utilities";
import { getURLWithCDN } from "discourse-common/lib/get-url";
import { helperContext } from "discourse-common/lib/helpers";

export default function buildOptions(options) {
  let context = helperContext();

  return {
    getURL: getURLWithCDN,
    currentUser: context.currentUser,
    censoredRegexp: context.site.censored_regexp,
    customEmojiTranslation: context.site.custom_emoji_translation,
    emojiDenyList: context.site.denied_emojis,
    siteSettings: context.siteSettings,
    formatUsername,
    watchedWordsReplace: transformWatchedWords(
      context.site.watched_words_replace
    ),
    watchedWordsLink: transformWatchedWords(context.site.watched_words_link),
    additionalOptions: context.site.markdown_additional_options,
    ...options,
  };
}

function transformWatchedWords(obj = {}) {
  return [...Object.entries(obj)].map(([key, value]) => {
    return [key, value.case_sensitive, value.word, value.replacement];
  });
}
