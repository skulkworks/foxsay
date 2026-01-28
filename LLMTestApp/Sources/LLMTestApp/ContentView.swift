import SwiftUI
import MLXLLM
import MLXLMCommon

struct TestCase {
    let input: String
    let expected: String
    let category: String
}

struct ContentView: View {
    @State private var modelId = "mlx-community/Qwen2.5-Coder-1.5B-Instruct-4bit"
    @State private var output = "Enter a model ID and click Run Tests\n"
    @State private var isRunning = false
    @State private var loadedContainer: ModelContainer?

    // Interactive prompt testing
    @State private var customPrompt = """
        Reverse the word order of the following text. Output ONLY the reversed words, nothing else.

        Text: {input}
        """
    @State private var customInput = "hello world this is a test"
    @State private var promptOutput = ""
    @State private var rawOutput = ""
    @State private var selectedTab = 0

    private let testCases: [TestCase] = [
        // Markdown
        TestCase(input: "hash this is a title", expected: "# this is a title", category: "markdown"),
        TestCase(input: "hash hash this is an h2", expected: "## this is an h2", category: "markdown"),
        TestCase(input: "hash hash hash heading three", expected: "### heading three", category: "markdown"),
        TestCase(input: "dash item one", expected: "- item one", category: "markdown"),

        // Bash
        TestCase(input: "git commit dash m fix bug", expected: "git commit -m fix bug", category: "bash"),
        TestCase(input: "ls dash la", expected: "ls -la", category: "bash"),
        TestCase(input: "curl dash dash verbose", expected: "curl --verbose", category: "bash"),
        TestCase(input: "npm install dash dash save dev", expected: "npm install --save-dev", category: "bash"),

        // JavaScript
        TestCase(input: "const x equals 5", expected: "const x = 5", category: "javascript"),
        TestCase(input: "function hello open paren close paren", expected: "function hello()", category: "javascript"),
        TestCase(input: "if x equals equals y", expected: "if x == y", category: "javascript"),
        TestCase(input: "console dot log open paren message close paren", expected: "console.log(message)", category: "javascript"),

        // Python
        TestCase(input: "def hello open paren close paren colon", expected: "def hello():", category: "python"),
        TestCase(input: "self dot value equals x", expected: "self.value = x", category: "python"),

        // Operators
        TestCase(input: "x plus equals 5", expected: "x += 5", category: "operators"),
        TestCase(input: "x not equals y", expected: "x != y", category: "operators"),
        TestCase(input: "x greater than y", expected: "x > y", category: "operators"),
        TestCase(input: "x less than y", expected: "x < y", category: "operators"),

        // Pass-through
        TestCase(input: "this is just regular text", expected: "this is just regular text", category: "passthrough"),
        TestCase(input: "hello world", expected: "hello world", category: "passthrough"),
    ]

    private let defaultPrompt = """
        Convert spoken punctuation to symbols. Be minimal - output only the converted text.

        Rules: hash=#, dash=-, dot=., equals=, colon=:, semicolon=;
        open paren=(, close paren=), open bracket=[, close bracket=]
        greater than=>, less than=<, plus=+
        "dash dash"=--, "equals equals"==, "not equals"=!=, "plus equals"=+=

        Examples:
        "hash title" -> # title
        "hash hash title" -> ## title
        "hash hash hash title" -> ### title
        "dash item" -> - item
        "curl dash dash verbose" -> curl --verbose
        "const x equals 5" -> const x = 5
        "let y equals 10" -> let y = 10
        "if x equals equals y" -> if x == y
        "x not equals y" -> x != y
        "x less than y" -> x < y
        "x greater than y" -> x > y
        "function hello open paren close paren" -> function hello()
        "def hello open paren close paren colon" -> def hello():
        "def foo open paren x close paren colon" -> def foo(x):
        "console dot log open paren msg close paren" -> console.log(msg)
        "hello world" -> hello world

        Input: {input}
        Output:
        """

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Model selector
            HStack {
                TextField("Model ID", text: $modelId)
                    .textFieldStyle(.roundedBorder)

                Button(isRunning ? "Loading..." : (loadedContainer == nil ? "Load Model" : "Reload")) {
                    loadModel()
                }
                .disabled(isRunning)
                .buttonStyle(.borderedProminent)

                if loadedContainer != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }

            // Tab picker
            Picker("Mode", selection: $selectedTab) {
                Text("Prompt Tester").tag(0)
                Text("Batch Tests").tag(1)
            }
            .pickerStyle(.segmented)

            if selectedTab == 0 {
                promptTesterView
            } else {
                batchTestsView
            }
        }
        .padding()
    }

    var promptTesterView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompt Template (use {input} as placeholder):")
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: $customPrompt)
                .font(.system(.body, design: .monospaced))
                .frame(height: 120)
                .border(Color.gray.opacity(0.3))

            HStack {
                Text("Input Text:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }

            TextField("Enter test input...", text: $customInput)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Test Prompt") {
                    testCustomPrompt()
                }
                .disabled(isRunning || loadedContainer == nil)
                .buttonStyle(.borderedProminent)

                if loadedContainer == nil {
                    Text("Load a model first")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                Spacer()
            }

            Divider()

            Text("Raw Output:")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView {
                Text(rawOutput.isEmpty ? "(no output yet)" : rawOutput)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: 80)
            .background(Color.black.opacity(0.05))
            .cornerRadius(4)

            Text("Cleaned Output:")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView {
                Text(promptOutput.isEmpty ? "(no output yet)" : promptOutput)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: 60)
            .background(Color.green.opacity(0.1))
            .cornerRadius(4)
        }
    }

    var batchTestsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(isRunning ? "Running..." : "Run All Tests") {
                    runTests()
                }
                .disabled(isRunning || loadedContainer == nil)
                .buttonStyle(.borderedProminent)

                if loadedContainer == nil {
                    Text("Load a model first")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            ScrollView {
                Text(output)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .background(Color.black.opacity(0.05))
            .cornerRadius(8)
        }
    }

    func loadModel() {
        isRunning = true
        output = "Loading model: \(modelId)\n"

        Task {
            do {
                loadedContainer = try await loadModelContainer(id: modelId)
                output += "Model loaded successfully!\n"
            } catch {
                output += "ERROR: \(error)\n"
                loadedContainer = nil
            }
            isRunning = false
        }
    }

    func testCustomPrompt() {
        guard let container = loadedContainer else { return }

        isRunning = true
        rawOutput = "Processing..."
        promptOutput = ""

        Task {
            let prompt = customPrompt.replacingOccurrences(of: "{input}", with: customInput)

            do {
                let raw = try await generate(container: container, prompt: prompt)
                rawOutput = raw
                promptOutput = cleanOutput(raw)
            } catch {
                rawOutput = "ERROR: \(error)"
                promptOutput = ""
            }

            isRunning = false
        }
    }

    func runTests() {
        guard let container = loadedContainer else { return }

        isRunning = true
        output = "Starting tests for: \(modelId)\n\n"

        Task {
            await runTestsAsync(container: container)
            isRunning = false
        }
    }

    @MainActor
    func runTestsAsync(container: ModelContainer) async {
        var passed = 0
        var categoryStats: [String: (p: Int, t: Int)] = [:]

        for (i, test) in testCases.enumerated() {
            let prompt = defaultPrompt.replacingOccurrences(of: "{input}", with: test.input)

            let raw: String
            do {
                raw = try await generate(container: container, prompt: prompt)
            } catch {
                raw = "ERROR"
            }

            let cleaned = cleanOutput(raw)
            let isPass = cleaned.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ==
                         test.expected.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

            if isPass {
                passed += 1
                output += "[\(i+1)] ✓ \(test.category)\n"
            } else {
                output += "[\(i+1)] ✗ \(test.category): \(test.input)\n"
                output += "    Expected: \(test.expected)\n"
                output += "    Got:      \(cleaned)\n"
            }

            var stats = categoryStats[test.category] ?? (p: 0, t: 0)
            stats.t += 1
            if isPass { stats.p += 1 }
            categoryStats[test.category] = stats
        }

        output += "\n=== RESULTS ===\n"
        for (cat, stats) in categoryStats.sorted(by: { $0.key < $1.key }) {
            output += "\(cat): \(stats.p)/\(stats.t)\n"
        }
        output += "\nTOTAL: \(passed)/\(testCases.count) (\(String(format: "%.0f", Double(passed)/Double(testCases.count)*100))%)\n"
    }

    func generate(container: ModelContainer, prompt: String) async throws -> String {
        let userInput = UserInput(prompt: prompt)
        let input = try await container.prepare(input: userInput)
        let parameters = GenerateParameters(maxTokens: 100, temperature: 0.1)

        var result = ""
        let stream = try await container.generate(input: input, parameters: parameters)
        for await generation in stream {
            if case .chunk(let chunk) = generation {
                result += chunk
            }
        }
        return result
    }

    func cleanOutput(_ output: String) -> String {
        var cleaned = output
        let endTokens = ["<end_of_turn>", "<|end|>", "<|eot_id|>", "</s>", "<|im_end|>", "<|endoftext|>", "<|assistant|>", "<|user|>"]
        for token in endTokens {
            if let r = cleaned.range(of: token) { cleaned = String(cleaned[..<r.lowerBound]) }
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            if let nl = cleaned.firstIndex(of: "\n") { cleaned = String(cleaned[cleaned.index(after: nl)...]) }
        }
        cleaned = cleaned.replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned
    }
}
