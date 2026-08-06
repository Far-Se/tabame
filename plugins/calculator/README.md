# Calculator — Tabame plugin

A fast launcher calculator for arithmetic, functions, saved formulas, unit
conversion, and currency conversion.

## Install

1. Make sure Python 3 is available on `PATH`.
2. Copy this folder to:

   ```text
   %localappdata%\Tabame\plugins\calculator\
   ```

3. Reopen the Tabame launcher. Tabame rescans plugins whenever the launcher is
   opened.
4. Type `calc` to open the calculator.

No third-party Python packages are required.

## Quick start

Type an expression after the `calc` keyword. Results update as you type:

```text
calc 2 + 2
calc sqrt(144) + 3^2
calc 200 usd to eur
calc 15 km to mi
calc 45 c to f
```

When the result is selected:

- Press **Enter** to save it as the next variable (`$a`, `$b`, `$c`, ...), add
  it to history, and clear the query.
- Open the **Ctrl+K** actions menu to copy the result or copy the full line
  (`expression = result`).

## Expressions

Whitespace is ignored. The calculator supports:

| Feature | Syntax | Example |
| --- | --- | --- |
| Addition, subtraction | `+`, `-` | `12 - 5` |
| Multiplication, division | `*`, `/` | `18 / 3` |
| Powers | `^` | `2^10` |
| Parentheses | `(...)` | `(10 + 5) * 2` |
| Percentage | postfix `%` | `250 * 15%` |
| Factorial | postfix `!` | `5!` |
| Scientific notation | `e` notation | `1.5e3` |

### Functions and constants

Single-argument functions:

```text
sqrt(x)  cbrt(x)  abs(x)    ln(x)    log(x)   log2(x)
exp(x)   sin(x)   cos(x)    tan(x)   asin(x)  acos(x)
atan(x)  sinh(x)  cosh(x)   tanh(x)  floor(x) ceil(x) round(x)
```

Multiple-argument functions:

```text
min(a, b, ...)
max(a, b, ...)
pow(a, b)
mod(a, b)
logb(value, base)
```

The constants `pi` and `e` are available. Trigonometric functions use degrees,
including the inverse functions:

```text
sin(90)
atan(1)
```

Factorials accept non-negative integers up to `170`.

## Unit conversion

Use `value unit to target`. Conversions can be chained:

```text
2.5 kg to lb
1 m to cm to in
3 gib to mb
```

Supported units and aliases are case-insensitive:

| Category | Units |
| --- | --- |
| Length | `mm`, `cm`, `m`, `km`, `in`, `ft`, `yd`, `mi`, `nmi` |
| Weight | `mg`, `g`, `kg`, `t`, `lb`, `oz` |
| Volume | `ml`, `cl`, `l`, `gal`, `qt`, `pt`, `cup`, `floz`, `tbsp`, `tsp` |
| Time | `s`, `min`, `h`, `day`, `week`, `month`, `year` |
| Data | `b`, `kb`, `mb`, `gb`, `tb`, `pb`, `kib`, `mib`, `gib`, `tib` |
| Temperature | `c` / `celsius`, `f` / `fahrenheit`, `k` / `kelvin` |

Full names are accepted for most physical units, such as `kilometers`,
`ounces`, `hours`, and `gallons`. Data units ending in `iB` use binary
multipliers; the other data units use decimal multipliers.

Arithmetic can be combined with conversions:

```text
(10 * 30% usd to ron) + 30
```

The value must have a unit before `to`, and both units must belong to the same
category.

## Currency conversion

Currency conversion uses the same syntax as other units:

```text
200 usd to eur
100 dollars to ron
50 eur to gbp to usd
```

Supported currency codes include:

```text
USD EUR RON GBP JPY CHF CAD AUD NZD CNY INR TRY PLN HUF CZK
SEK NOK DKK BRL MXN ZAR KRW SGD HKD THB IDR PHP MYR ILS BGN ISK
```

Common names such as `dollars`, `euros`, `lei`, `pounds`, `yen`, `francs`,
`yuan`, `rupees`, `pesos`, `rand`, and `won` are also recognized where
available.

Rates are fetched lazily from Frankfurter/ECB when a currency expression needs
them, then cached for six hours. If the live request fails, the plugin uses a
cached rate set; on first use without a cache it falls back to approximate
built-in rates and marks the result as a fallback. Use **Refresh Currency Rates**
from the launcher actions menu to force a new request.

## Saved variables

Press **Enter** on a result to save it as the next automatically named variable:

```text
calc 120 / 8
# Press Enter: saves $a = 15

calc $a * 4
```

Variables and their formulas are persisted by Tabame between launcher sessions.
They can be used in later expressions, and formulas can refer to earlier
variables such as `$a` or `$b`.

Select a saved variable and press **Enter** to edit its formula. The editor
recalculates the value when saved and rejects invalid or circular references.
The variable actions menu also provides **Use in Expression** and **Copy Value**.

## History and actions

Saved results appear in history. For a history item:

- Press **Enter** to reuse its expression.
- Use **Ctrl+K** to reuse, copy the result, or remove the item.
- Choose **Clear History** to remove all saved calculations.

Other available actions include:

- **Refresh Currency Rates** — bypass the current rate cache.
- **Clear Variables** (`Ctrl+Shift+C`) — remove all saved variables and formulas.
- **Clear History** (`Ctrl+Shift+H`) — remove all saved calculation history.

History and variables use Tabame storage, so they are separate from the
calculator source files and survive reopening the launcher.
