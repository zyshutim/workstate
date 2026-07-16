# Workstate Color System

The color source of truth is the Smartisan OS UI Kit in Figma:

- Themes: `https://www.figma.com/design/ELMYqvHUjT8dIqmNP2ch9d/?node-id=273-358`
- Colors: `https://www.figma.com/design/ELMYqvHUjT8dIqmNP2ch9d/?node-id=274-384`
- Gradients: `https://www.figma.com/design/ELMYqvHUjT8dIqmNP2ch9d/?node-id=315-759`

## Rules

- Exact source values live only in `Sources/WorkstateUI/SmartisanColorTokens.swift`.
- Product views consume semantic names from `WorkstateTheme`; do not add raw RGB, hex, AppKit system colors, or SwiftUI semantic colors directly in feature views.
- Neutral tokens define surfaces, separators, text, grid, relation lines, and shadows.
- Brand, Success, Warning, and Danger are state semantics. Do not use project identity colors to represent success, warning, or failure.
- Theme gradients define project identity. Use their representative color for thin lines, text, and small symbols; reserve the full gradient for filled, high-emphasis surfaces.
- Button and App Bar gradients are control-state tokens. Enabled and pressed values must not be approximated with opacity.
- Dark mode remaps the same Neutral and header tokens. Opacity may express depth, focus, hover, and glass layering, but must not introduce a new hue.
- When adding a new color role, add the raw Figma value first, then its semantic mapping in `WorkstateTheme`, then use the semantic name in the view.
