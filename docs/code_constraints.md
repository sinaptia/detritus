# Code constraints

Before implementing ANY feature, understand these constraints:

## 1. Check Line Count Budget

```bash
wc -l detritus.rb          # Current count - target ~245 lines
git log --oneline -5       # What's been changing lately
```

**Rule**: New features must justify their line count. Prefer deletion over addition.

## 2. Know RubyLLM (The Foundation)

You're building ON RubyLLM, not replacing it. must have docs at hand: ./docs/ruby_llm.md for a navigational map of the official docs


## 3. Ruby Idioms > Algorithms

* Take advantage of Ruby's expressivenes.
* use Enumerable whenever possible.
* String, Hash, Array have a load of super expressive methods. Use them.
* Apply principle of least surprise

## 4. Configuration Is Debt

Ask before adding config: "Does user NEED choice, or am I afraid of the wrong default?"

Start with hardcoded sensible behavior. Add config only when use cases diverge.

## 5. Implementation Checklist

Before committing code:

- [ ] Could Ruby handle this instead of custom code?
- [ ] Could RubyLLM handle this instead of custom code?
- [ ] Could be written in more idiomatic ruby?
- [ ] Did I run tests?

## Example: the compaction feature journey

**Wrong path (initial agent implementation)**: ~300+ lines
- Custom serialization layer for messages
- Manual token estimation and counting
- Iterative cutting logic
- Multiple config options
- Several helper methods

**Right path (after distillation)**:
 * single method ~20 lines
 * ruby primitives for array/enumerable manipulation
 * uses RubyLLM::Chat object we already have and the standard API of the lib
 * every line does something highly valuable, meaningfull

**_Less code, more power. That's the way._**
