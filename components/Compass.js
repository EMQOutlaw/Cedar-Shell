.pragma library
// Quick answers for the launchers: arithmetic typed into the search field and
// a web search for whatever else. Pure functions, no shell access.

var engines = [
    { id: "brave", label: "Brave Search", url: "https://search.brave.com/search?q=%s" },
    { id: "duckduckgo", label: "DuckDuckGo", url: "https://duckduckgo.com/?q=%s" },
    { id: "startpage", label: "Startpage", url: "https://www.startpage.com/do/search?q=%s" },
    { id: "kagi", label: "Kagi", url: "https://kagi.com/search?q=%s" },
    { id: "google", label: "Google", url: "https://www.google.com/search?q=%s" }
];
function engine(id) {
    for (var i = 0; i < engines.length; ++i) if (engines[i].id === id) return engines[i];
    return engines[0];
}
function searchUrl(id, query) {
    return engine(id).url.replace("%s", encodeURIComponent(String(query || "").trim()));
}

// "example.com", "docs.rs/serde" or a full URL: open it directly.
function urlFor(query) {
    var text = String(query || "").trim();
    if (!text || /\s/.test(text)) return "";
    if (/^https?:\/\/\S+$/i.test(text)) return text;
    if (/^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+(:\d+)?(\/\S*)?$/i.test(text)
        && /\.(com|org|net|io|dev|rs|app|edu|gov|me|co|uk|de|fr|ca|us|sh|xyz|info|ai|tv|gg)(:|\/|$)/i.test(text))
        return "https://" + text;
    return "";
}

// ---------------------------------------------------------------- calculator
var functions = {
    sqrt: Math.sqrt, cbrt: Math.cbrt, abs: Math.abs, round: Math.round, floor: Math.floor, ceil: Math.ceil,
    sin: Math.sin, cos: Math.cos, tan: Math.tan, asin: Math.asin, acos: Math.acos, atan: Math.atan,
    ln: Math.log, log: Math.log10, log2: Math.log2, exp: Math.exp, min: Math.min, max: Math.max
};
var constants = { pi: Math.PI, e: Math.E, tau: Math.PI * 2 };

function tokenize(text) {
    var source = String(text || "").replace(/(\d),(?=\d{3}(\D|$))/g, "$1").replace(/[×]/g, "*").replace(/[÷]/g, "/").replace(/\*\*/g, "^").replace(/(\d)\s*[xX]\s*(?=[\d(.])/g, "$1*");
    var tokens = [], i = 0;
    while (i < source.length) {
        var ch = source[i];
        if (/\s/.test(ch)) { ++i; continue; }
        var number = /^(\d+\.?\d*|\.\d+)(e[+-]?\d+)?/i.exec(source.slice(i));
        if (number) { tokens.push({ type: "number", value: parseFloat(number[0]) }); i += number[0].length; continue; }
        var word = /^[a-z_][a-z0-9_]*/i.exec(source.slice(i));
        if (word) { tokens.push({ type: "word", value: word[0].toLowerCase() }); i += word[0].length; continue; }
        if ("+-*/^%(),".indexOf(ch) >= 0) { tokens.push({ type: "op", value: ch }); ++i; continue; }
        return null;
    }
    return tokens;
}

// Recursive descent: sum > product > unary > power > postfix (%) > atom.
function parse(tokens) {
    var at = 0, usedOperator = false, usedNumber = false;
    function peek() { return tokens[at]; }
    function take() { return tokens[at++]; }
    function isOp(value) { var t = peek(); return t && t.type === "op" && t.value === value; }
    function isWord(value) { var t = peek(); return t && t.type === "word" && t.value === value; }
    function sum() {
        var left = product();
        while (isOp("+") || isOp("-")) { var op = take().value; usedOperator = true; var right = product(); left = op === "+" ? left + right : left - right; }
        return left;
    }
    function product() {
        var left = unary();
        for (;;) {
            if (isOp("*") || isOp("/") || isWord("x") || isWord("of") || isWord("mod")) {
                var op = take().value; usedOperator = true; var right = unary();
                left = op === "/" ? left / right : op === "mod" ? left % right : left * right;
            } else if (peek() && (peek().type === "number" || isOp("(") || (peek().type === "word" && peek().value !== "x" && peek().value !== "of" && peek().value !== "mod"))) {
                usedOperator = true; left = left * unary(); // implicit multiplication: 2pi, 3(4+1)
            } else return left;
        }
    }
    function unary() {
        if (isOp("-")) { take(); return -unary(); }
        if (isOp("+")) { take(); return unary(); }
        return power();
    }
    function power() {
        var base = postfix();
        if (isOp("^")) { take(); usedOperator = true; return Math.pow(base, unary()); }
        return base;
    }
    function postfix() {
        var value = atom();
        while (isOp("%")) { take(); usedOperator = true; value = value / 100; }
        return value;
    }
    function atom() {
        var token = take();
        if (!token) throw new Error("expected a value");
        if (token.type === "number") { usedNumber = true; return token.value; }
        if (token.type === "op" && token.value === "(") {
            var inner = sum();
            if (!isOp(")")) throw new Error("expected )");
            take(); return inner;
        }
        if (token.type === "word") {
            if (functions[token.value] && isOp("(")) {
                take(); usedOperator = true;
                var args = [sum()];
                while (isOp(",")) { take(); args.push(sum()); }
                if (!isOp(")")) throw new Error("expected )");
                take();
                return functions[token.value].apply(null, args);
            }
            if (constants.hasOwnProperty(token.value)) return constants[token.value];
        }
        throw new Error("unexpected " + token.value);
    }
    var result = sum();
    if (at !== tokens.length) throw new Error("trailing input");
    return { value: result, meaningful: usedOperator && usedNumber };
}

function format(value) {
    if (!isFinite(value)) return "";
    var magnitude = Math.abs(value);
    if (magnitude !== 0 && (magnitude >= 1e15 || magnitude < 1e-6)) return value.toExponential(6).replace(/\.?0+e/, "e");
    var text = String(parseFloat(value.toPrecision(12)));
    var parts = text.split(".");
    parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",");
    return parts.join(".");
}

// A result only for something that reads as arithmetic: at least one number
// and one operator or function, and nothing left over. Bare numbers and app
// names return null.
function evaluate(text) {
    var tokens = tokenize(text);
    if (!tokens || tokens.length < 2) return null;
    try {
        var parsed = parse(tokens);
        if (!parsed.meaningful || !isFinite(parsed.value)) return null;
        var display = format(parsed.value);
        return display ? { value: parsed.value, display: display, expression: String(text).trim() } : null;
    } catch (_) { return null; }
}
