export function createWatchedWordRegExp(regexp, caseSensitive) {
  const caseFlag = caseSensitive ? "" : "i";
  return new RegExp(regexp, `${caseFlag}gu`);
}

export function toWatchedWord(regexp) {
  const [[regexpString, options]] = Object.entries(regexp);
  return { ...options, regexp: regexpString };
}
