/**
 * Turns `> Tip: …`, `> Note: …` and `> Warning: …` blockquotes into labelled callouts.
 * Authors keep writing plain Markdown; the label becomes the callout title.
 */
const pattern = /^(Tip|Note|Warning):\s*/;

function firstParagraph(node) {
  return node.children?.find((child) => child.type === "element" && child.tagName === "p");
}

function transform(node) {
  if (node.type === "element" && node.tagName === "blockquote") {
    const paragraph = firstParagraph(node);
    const text = paragraph?.children?.[0];
    const match = text?.type === "text" ? text.value.match(pattern) : null;
    if (match) {
      const kind = match[1].toLowerCase();
      text.value = text.value.slice(match[0].length);
      node.tagName = "aside";
      node.properties = { className: ["callout", kind] };
      node.children.unshift({
        type: "element", tagName: "p", properties: { className: ["callout-title"] },
        children: [{ type: "text", value: match[1] }],
      });
      return;
    }
  }
  node.children?.forEach(transform);
}

export default function rehypeCallouts() {
  return (tree) => transform(tree);
}
