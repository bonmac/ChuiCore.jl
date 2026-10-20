# Reference: documented internals

Internal names (the third tier of ADR-0005) that carry a docstring. **No stability promise:**
they may change in any release, and no contract entry names them. They are listed so the
public docstrings can link to them.

```@autodocs
Modules = [ChuiCore]
Public = false
Filter = t -> t !== ChuiCore
```
