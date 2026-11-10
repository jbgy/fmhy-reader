import Foundation

// Parser canary — parses the live fmhy/edit markdown with the app's own parser
// and fails when a section silently loses structure after an upstream edit.
//
//   swiftc -O fmhy/Models/WikiModels.swift fmhy/Models/WikiInstances.swift \
//     fmhy/Services/FMHYMarkdownParser.swift scripts/parser-canary/main.swift \
//     -o build/parser-canary
//
//   ./build/parser-canary --write-baseline \
//       --seed-dir fmhy/Resources/WikiSeed \
//       --out scripts/parser-canary/baseline.json
//   ./build/parser-canary --check \
//       --baseline scripts/parser-canary/baseline.json
//
// A drop is only suspicious; growth is normal. The check fails when a section
// loses more than `dropTolerance` of its entries, loses a category, loses every
// entry it used to have, or cannot be fetched at all.

struct Counts: Codable {
    let entries: Int
    let categories: Int
    let groups: Int
}

struct BaselineFile: Codable {
    let generated: String
    let commit: String?
    let sections: [String: Counts]
    let totalEntries: Int
}

let dropTolerance = 0.9
let rawBase = "https://raw.githubusercontent.com/fmhy/edit/main/docs/"

func usage() -> Never {
    FileHandle.standardError.write(Data("""
    usage: parser-canary --check --baseline FILE
           parser-canary --write-baseline --seed-dir DIR --out FILE
    """.utf8))
    exit(2)
}

func parseOptions() -> (write: Bool, baseline: String, seedDir: String, out: String) {
    var write = false
    var baseline = "scripts/parser-canary/baseline.json"
    var seedDir = "fmhy/Resources/WikiSeed"
    var out = baseline
    var args = Array(CommandLine.arguments.dropFirst())
    var index = 0

    while index < args.count {
        let argument = args[index]
        switch argument {
        case "--check":
            write = false
        case "--write-baseline":
            write = true
        case "--baseline", "--seed-dir", "--out":
            guard index + 1 < args.count else { usage() }
            let value = args[index + 1]
            if argument == "--baseline" { baseline = value }
            if argument == "--seed-dir" { seedDir = value }
            if argument == "--out" { out = value }
            args.remove(at: index)
            args.remove(at: index)
            continue
        default:
            usage()
        }
        index += 1
    }
    return (write, baseline, seedDir, out)
}

func counts(markdown: String, slug: String, title: String) -> Counts {
    let page = FMHYMarkdownParser.parse(markdown: markdown, slug: slug, title: title)
    return Counts(
        entries: page.entryCount,
        categories: page.categories.count,
        groups: page.categories.reduce(0) { $0 + $1.groups.count }
    )
}

func fetch(_ url: URL) throws -> Data {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<Data, Error> = .failure(URLError(.unknown))

    var request = URLRequest(url: url)
    request.timeoutInterval = 30
    request.setValue("fmhy-reader-canary", forHTTPHeaderField: "User-Agent")

    URLSession(configuration: .ephemeral).dataTask(with: request) { data, response, error in
        defer { semaphore.signal() }
        if let error {
            result = .failure(error)
            return
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            result = .failure(URLError(.badServerResponse))
            return
        }
        result = .success(data ?? Data())
    }.resume()

    semaphore.wait()
    return try result.get()
}

func seedCommit(in directory: String) -> String? {
    let url = URL(fileURLWithPath: directory).appendingPathComponent("manifest.json")
    guard let data = try? Data(contentsOf: url),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return object["commit"] as? String
}

func writeBaseline(seedDir: String, out: String) {
    var sections: [String: Counts] = [:]
    var missing: [String] = []

    for definition in WikiCatalog.pages {
        let url = URL(fileURLWithPath: seedDir).appendingPathComponent("\(definition.slug).md")
        guard let markdown = try? String(contentsOf: url, encoding: .utf8) else {
            missing.append(definition.slug)
            continue
        }
        sections[definition.slug] = counts(
            markdown: markdown,
            slug: definition.slug,
            title: definition.title
        )
    }

    let baseline = BaselineFile(
        generated: ISO8601DateFormatter().string(from: Date()),
        commit: seedCommit(in: seedDir),
        sections: sections,
        totalEntries: sections.values.reduce(0) { $0 + $1.entries }
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
        try encoder.encode(baseline).write(to: URL(fileURLWithPath: out))
    } catch {
        FileHandle.standardError.write(Data("error: could not write \(out): \(error)\n".utf8))
        exit(2)
    }

    print("baseline written to \(out): \(sections.count) sections, \(baseline.totalEntries) entries")
    if !missing.isEmpty {
        print("missing seed files (not in baseline): \(missing.joined(separator: ", "))")
    }
}

func check(baselinePath: String) -> Int32 {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: baselinePath)),
          let baseline = try? JSONDecoder().decode(BaselineFile.self, from: data)
    else {
        FileHandle.standardError.write(Data("error: cannot read baseline \(baselinePath)\n".utf8))
        return 2
    }

    var failures: [String] = []
    var liveTotal = 0
    var rows: [(slug: String, before: Int, after: Int, status: String)] = []

    for definition in WikiCatalog.pages {
        let url = URL(string: rawBase + definition.slug + ".md")!
        let markdown: String
        do {
            guard let text = String(data: try fetch(url), encoding: .utf8) else {
                throw URLError(.cannotDecodeContentData)
            }
            markdown = text
        } catch {
            failures.append("\(definition.slug): could not fetch or decode the live page")
            rows.append((definition.slug, baseline.sections[definition.slug]?.entries ?? 0, 0, "FETCH FAILED"))
            continue
        }

        let live = counts(markdown: markdown, slug: definition.slug, title: definition.title)
        liveTotal += live.entries

        guard let known = baseline.sections[definition.slug] else {
            // A section added to the catalog since the baseline was written.
            let status = live.entries > 0 ? "new" : "NEW BUT EMPTY"
            if live.entries == 0 { failures.append("\(definition.slug): new section parses to zero entries") }
            rows.append((definition.slug, 0, live.entries, status))
            continue
        }

        var status = "ok"
        if live.entries == 0, known.entries > 0 {
            status = "EMPTY"
            failures.append("\(definition.slug): was \(known.entries) entries, now parses to 0")
        } else if live.entries < Int(Double(known.entries) * dropTolerance) {
            status = "DROPPED"
            failures.append("\(definition.slug): was \(known.entries) entries, now \(live.entries)")
        } else if live.categories < known.categories {
            status = "NO CATEGORIES"
            failures.append("\(definition.slug): was \(known.categories) categories, now \(live.categories)")
        } else if live.entries > known.entries {
            status = "grew"
        }

        rows.append((definition.slug, known.entries, live.entries, status))
    }

    let width = rows.map(\.slug.count).max() ?? 10
    print("section".padding(toLength: width, withPad: " ", startingAt: 0) + "   baseline   live   status")
    for row in rows {
        let name = row.slug.padding(toLength: width, withPad: " ", startingAt: 0)
        print("\(name)   \(String(row.before).leftPadded(8))   \(String(row.after).leftPadded(4))   \(row.status)")
    }

    let baselineTotal = baseline.sections.values.reduce(0) { $0 + $1.entries }
    print("")
    print("total entries: baseline \(baselineTotal), live \(liveTotal)")
    if baselineTotal > 0 {
        let delta = Double(liveTotal - baselineTotal) / Double(baselineTotal) * 100
        let formatted = String(format: "%+.1f%%", delta)
        print("change: \(formatted)")
        if delta < -5 {
            failures.append("total entries dropped \(formatted)")
        }
    }

    guard failures.isEmpty else {
        print("")
        print("parser canary failed:")
        for failure in failures { print("  - \(failure)") }
        return 1
    }

    print("")
    print("parser canary ok")
    return 0
}

extension String {
    func leftPadded(_ width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}

let options = parseOptions()
if options.write {
    writeBaseline(seedDir: options.seedDir, out: options.out)
    exit(0)
}
exit(check(baselinePath: options.baseline))
