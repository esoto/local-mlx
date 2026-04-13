import Foundation

/// A curated selection of mlx-community models users can pick from
/// without having to remember HuggingFace paths. `mlx_lm.server`
/// auto-downloads a model the first time it's requested, so selecting
/// an entry here and clicking "Start Server" (or "Download Model" to
/// pre-fetch with progress bars) will fetch the weights on first
/// launch into `~/.cache/huggingface/` and reuse them after.
///
/// Entries are deliberately limited to quantised (4-bit / QAT-4bit)
/// builds from the `mlx-community/` HuggingFace namespace — the
/// variants most likely to fit in a consumer Apple-silicon machine.
/// Sizes are approximate disk footprints, not memory requirements.
///
/// `isVision` is orthogonal to `family`: vision-capable models are
/// flagged wherever they naturally live (Qwen2-VL under Qwen, LLaVA
/// under Mistral, Gemma 3 / Gemma 4 E4B under Gemma) so the picker's
/// family grouping stays intuitive and the eye icon on vision
/// entries is the signal that tells you they use `mlx_vlm.server`.
struct MLXModelEntry: Identifiable, Hashable, Sendable {
    /// HuggingFace repo id, also used as the stable identifier.
    /// Passed directly to `mlx_lm.server --model` (text) or
    /// `mlx_vlm.server --model` (vision).
    let id: String
    /// Short, human-friendly label for menus.
    let displayName: String
    /// Longer, one-line description shown alongside the name.
    let blurb: String
    /// Model family for grouping in the picker.
    let family: Family
    /// Approximate on-disk size in gigabytes. For menu badges and
    /// "will this fit" hints — not exact.
    let approxSizeGB: Double
    /// Whether this model understands images. Vision models require
    /// `mlx_vlm.server` to host them; text models run on `mlx_lm.server`.
    /// The ServerLauncher picks the right module based on this flag.
    let isVision: Bool

    init(id: String,
         displayName: String,
         blurb: String,
         family: Family,
         approxSizeGB: Double,
         isVision: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.blurb = blurb
        self.family = family
        self.approxSizeGB = approxSizeGB
        self.isVision = isVision
    }

    enum Family: String, CaseIterable, Sendable {
        case llama = "Llama"
        case qwen = "Qwen"
        case mistral = "Mistral"
        case phi = "Phi"
        case gemma = "Gemma"
    }
}

enum MLXModelCatalog {

    /// Popular 4-bit mlx-community builds. Ordered roughly small → large
    /// within each family so the picker reads naturally. Vision entries
    /// sit next to their text counterparts in whichever family they
    /// belong to — the eye icon in the picker marks them.
    static let builtIn: [MLXModelEntry] = [

        // MARK: Llama
        MLXModelEntry(
            id: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            displayName: "Llama 3.2 1B Instruct",
            blurb: "Tiny, very fast — good for quick Q&A and drafting.",
            family: .llama,
            approxSizeGB: 0.7),
        MLXModelEntry(
            id: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            displayName: "Llama 3.2 3B Instruct",
            blurb: "Small & fast. Solid all-round chat model.",
            family: .llama,
            approxSizeGB: 1.8),
        MLXModelEntry(
            id: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit",
            displayName: "Llama 3.1 8B Instruct",
            blurb: "Medium quality/speed tradeoff. Needs ~6 GB free RAM.",
            family: .llama,
            approxSizeGB: 4.5),

        // MARK: Qwen
        MLXModelEntry(
            id: "mlx-community/Qwen2.5-7B-Instruct-4bit",
            displayName: "Qwen 2.5 7B Instruct",
            blurb: "Strong generalist, good at reasoning and code.",
            family: .qwen,
            approxSizeGB: 4.2),
        MLXModelEntry(
            id: "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit",
            displayName: "Qwen 2.5 Coder 7B Instruct",
            blurb: "Tuned for code. Drop-in for programming sessions.",
            family: .qwen,
            approxSizeGB: 4.2),
        MLXModelEntry(
            id: "mlx-community/Qwen2.5-Coder-14B-Instruct-4bit",
            displayName: "Qwen 2.5 Coder 14B Instruct",
            blurb: "Higher-quality code model. Needs ~10 GB free RAM.",
            family: .qwen,
            approxSizeGB: 8.3),
        MLXModelEntry(
            id: "mlx-community/Qwen2-VL-7B-Instruct-4bit",
            displayName: "Qwen 2 VL 7B Instruct",
            blurb: "Vision + text. Strong at OCR and image Q&A.",
            family: .qwen,
            approxSizeGB: 4.5,
            isVision: true),

        // MARK: Mistral
        MLXModelEntry(
            id: "mlx-community/Mistral-7B-Instruct-v0.3-4bit",
            displayName: "Mistral 7B Instruct v0.3",
            blurb: "Classic European open model. Good instruction following.",
            family: .mistral,
            approxSizeGB: 4.1),
        MLXModelEntry(
            id: "mlx-community/llava-v1.6-mistral-7b-4bit",
            displayName: "LLaVA 1.6 (Mistral 7B)",
            blurb: "Classic multimodal model, good general image understanding.",
            family: .mistral,
            approxSizeGB: 4.4,
            isVision: true),

        // MARK: Phi
        MLXModelEntry(
            id: "mlx-community/Phi-3.5-mini-instruct-4bit",
            displayName: "Phi 3.5 Mini Instruct",
            blurb: "Small Microsoft model, punches above its weight.",
            family: .phi,
            approxSizeGB: 2.2),
        MLXModelEntry(
            id: "mlx-community/Phi-3.5-vision-instruct-4bit",
            displayName: "Phi 3.5 Vision Instruct",
            blurb: "Small Microsoft vision model — fits on 8 GB machines.",
            family: .phi,
            approxSizeGB: 2.5,
            isVision: true),

        // MARK: Gemma
        MLXModelEntry(
            id: "mlx-community/gemma-2-2b-it-4bit",
            displayName: "Gemma 2 2B Instruct",
            blurb: "Very small Google model — fast loads, text only.",
            family: .gemma,
            approxSizeGB: 1.7),
        MLXModelEntry(
            id: "mlx-community/gemma-2-9b-it-4bit",
            displayName: "Gemma 2 9B Instruct",
            blurb: "Higher-quality Gemma build, text only. Needs ~7 GB free RAM.",
            family: .gemma,
            approxSizeGB: 5.4),
        MLXModelEntry(
            id: "mlx-community/gemma-3-4b-it-4bit",
            displayName: "Gemma 3 4B Instruct",
            blurb: "First vision-capable Gemma. SigLIP vision encoder at 896×896.",
            family: .gemma,
            approxSizeGB: 2.5,
            isVision: true),
        MLXModelEntry(
            id: "mlx-community/gemma-4-e4b-it-4bit",
            displayName: "Gemma 4 E4B Instruct",
            blurb: "Elastic multimodal (text + image + video + audio). Needs a recent mlx-vlm.",
            family: .gemma,
            approxSizeGB: 2.8,
            isVision: true),
    ]

    /// Look up a catalog entry by its HF path. Returns nil for custom
    /// user-entered paths that aren't in the curated list.
    static func find(_ id: String) -> MLXModelEntry? {
        builtIn.first(where: { $0.id == id })
    }

    /// Catalog grouped by family, preserving within-family order. Used
    /// by the menu to render sectioned entries.
    static var groupedByFamily: [(family: MLXModelEntry.Family, entries: [MLXModelEntry])] {
        MLXModelEntry.Family.allCases.compactMap { family in
            let entries = builtIn.filter { $0.family == family }
            return entries.isEmpty ? nil : (family: family, entries: entries)
        }
    }
}
