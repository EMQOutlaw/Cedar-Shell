.pragma library
// Ordered subsequence matching, with prefix, word-boundary and adjacency bonuses.
function score(query, text) {
    query = query.toLowerCase().trim(); text = text.toLowerCase();
    if (!query) return 0;
    let position = -1, total = 0;
    for (let i = 0; i < query.length; ++i) {
        const next = text.indexOf(query[i], position + 1);
        if (next < 0) return -1;
        total += 10 + (next === position + 1 ? 8 : 0) + (next === 0 || /[\s\-_]/.test(text[next - 1]) ? 10 : 0);
        total -= Math.min(8, next - position - 1); position = next;
    }
    return total + (text.startsWith(query) ? 30 : 0) - text.length * 0.01;
}
