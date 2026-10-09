import Foundation

enum HTMLTemplate {
    /// marked.min.js bundled in Resources (offline GitHub-flavored markdown).
    private static let markedJS: String = {
        guard let u = Bundle.main.url(forResource: "marked.min", withExtension: "js"),
              let s = try? String(contentsOf: u, encoding: .utf8) else { return "" }
        return s
    }()

    /// JSON-encode the markdown source so it can be embedded as a JS string
    /// literal without any escaping/injection hazard.
    private static func jsString(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed]),
              let json = String(data: data, encoding: .utf8) else { return "\"\"" }
        // HTML parsing sees closing script tags before JavaScript string parsing.
        return json.replacingOccurrences(of: "<", with: "\\u003c")
    }

    static func render(markdown: String) -> String {
        let nonce = UUID().uuidString
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'nonce-\(nonce)'; style-src 'unsafe-inline'; img-src file: data: https: http:; base-uri 'none'; form-action 'none'">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(css)</style>
        <script nonce="\(nonce)">\(markedJS)</script>
        </head>
        <body>
        <article id="content"></article>
        <script nonce="\(nonce)">
        marked.setOptions({ gfm: true, breaks: false });
        document.getElementById('content').innerHTML = marked.parse(\(jsString(markdown)));
        \(SearchScript.source)
        </script>
        </body>
        </html>
        """
    }

    private static let css = """
    :root {
      --bg: #1c1c1f;
      --fg: #d6d6d9;
      --muted: #8a8a93;
      --accent: #7aa2f7;
      --border: #2e2e33;
      --code-bg: #252529;
    }
    * { box-sizing: border-box; }
    html, body { background: transparent; margin: 0; }
    body {
      color: var(--fg);
      font: 16px/1.7 -apple-system, "SF Pro Text", system-ui, sans-serif;
      -webkit-font-smoothing: antialiased;
      padding: 56px 44px 80px;
    }
    #content { max-width: 760px; margin: 0 auto; }
    h1, h2, h3, h4, h5, h6 {
      font-weight: 600; line-height: 1.3;
      margin: 1.6em 0 0.6em; color: #fff;
    }
    h1 { font-size: 1.9em; margin-top: 0; }
    h2 { font-size: 1.5em; padding-bottom: .3em; border-bottom: 1px solid var(--border); }
    h3 { font-size: 1.25em; }
    h4 { font-size: 1.05em; }
    p, ul, ol, blockquote, table, pre { margin: 0 0 1em; }
    a { color: var(--accent); text-decoration: none; }
    a:hover { text-decoration: underline; }
    strong { color: #fff; font-weight: 600; }
    ul, ol { padding-left: 1.6em; }
    li { margin: .25em 0; }
    blockquote {
      margin-left: 0; padding: .2em 1em;
      border-left: 3px solid var(--border); color: var(--muted);
    }
    code {
      font: 0.88em "SF Mono", ui-monospace, "JetBrains Mono", Menlo, monospace;
      background: var(--code-bg); padding: .15em .4em; border-radius: 5px;
    }
    pre {
      background: var(--code-bg); padding: 14px 16px;
      border-radius: 10px; overflow-x: auto; border: 1px solid var(--border);
    }
    pre code { background: none; padding: 0; }
    hr { border: none; border-top: 1px solid var(--border); margin: 2em 0; }
    img { max-width: 100%; border-radius: 8px; }
    table { border-collapse: collapse; width: 100%; }
    th, td { border: 1px solid var(--border); padding: .5em .8em; text-align: left; }
    th { background: var(--code-bg); }
    table tr:nth-child(2n) { background: rgba(255,255,255,.02); }
    input[type="checkbox"] { margin-right: .4em; }
    ::selection { background: rgba(122,162,247,.35); }
    ::-webkit-scrollbar { width: 9px; height: 9px; }
    ::-webkit-scrollbar-thumb { background: #3a3a40; border-radius: 5px; }
    ::-webkit-scrollbar-thumb:hover { background: #4a4a52; }
    """
}
