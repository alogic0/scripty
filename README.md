# Scripty

Scripty is a tiny scripting language meant to be embedded in strings or other
similar constructs within a host document.

Scripty supports only the basic syntax necessary to build expressions:
 - access fields (eg `$foo.bar`)
 - call functions (eg `$foo.baz()`)
 - refer to basic literals (`'string'`, `"string"`, `10`, `0.5`, `true`, `false`)

The evaluation context for a Scripty expression is entirely defined by you.

As an example Scripty is used by the [Zine](https://zine-ssg.io) static site generator for templating HTML:

```html
<ctx about="$site.page('about')">
  <a href="$ctx.about.link()" text="$ctx.about.title"></a>
</ctx>
```

This example contains three Scripty expressions:

- `$site.page('about')`
- `$ctx.about.link()`
- `$ctx.about.title`


# Usage

See `examples/basic.zig`. Note that the API is not fully polished yet and it might change in the future.