export class MentionsParser {
  constructor(prettyText) {
    this.prettyText = prettyText;
  }

  parse(markdown) {
    const tokens = this.prettyText.parse(markdown);
    const mentions = this.#parse(tokens);
    return [...new Set(mentions)];
  }

  #parse(tokens) {
    const mentions = [];
    let insideMention = false;
    for (const token of tokens) {
      if (token.children) {
        this.#parse(token.children).forEach((mention) =>
          mentions.push(mention)
        );
      } else {
        if (token.type === "mention_open") {
          insideMention = true;
          continue;
        }

        if (insideMention && token.type === "text") {
          mentions.push(this.#truncateMention(token.content));
          insideMention = false;
        }
      }
    }

    return mentions;
  }

  #truncateMention(mention) {
    return mention.substring(1).trim();
  }
}
