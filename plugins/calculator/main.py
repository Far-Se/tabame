#!/usr/bin/env python3
"""
Calculator — a Tabame launcher plugin.

Extended math (functions, constants, %, !, ^) plus inline currency and
unit conversion via a natural "to" keyword, e.g.:

    (10 * 30% usd to ron) + 30
    15 km to mi
    45 c to f
    sqrt(144) + 3^2

Protocol: newline-delimited JSON over stdin/stdout, per the Tabame plugin spec.
"""

import json
import math
import os
import re
import sys
import time
import urllib.error
import urllib.request

# --------------------------------------------------------------------------
# Wire protocol helpers
# --------------------------------------------------------------------------


def send(frame):
    sys.stdout.write(json.dumps(frame, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def log(*a):
    print(*a, file=sys.stderr, flush=True)


# --------------------------------------------------------------------------
# Unit / currency tables
# --------------------------------------------------------------------------

LENGTH_FACTORS = {
    "mm": 0.001,
    "cm": 0.01,
    "m": 1.0,
    "km": 1000.0,
    "in": 0.0254,
    "ft": 0.3048,
    "yd": 0.9144,
    "mi": 1609.344,
    "nmi": 1852.0,
}
LENGTH_ALIASES = {
    "mm": "mm",
    "millimeter": "mm",
    "millimeters": "mm",
    "millimetre": "mm",
    "millimetres": "mm",
    "cm": "cm",
    "centimeter": "cm",
    "centimeters": "cm",
    "centimetre": "cm",
    "centimetres": "cm",
    "m": "m",
    "meter": "m",
    "meters": "m",
    "metre": "m",
    "metres": "m",
    "km": "km",
    "kilometer": "km",
    "kilometers": "km",
    "kilometre": "km",
    "kilometres": "km",
    "in": "in",
    "inch": "in",
    "inches": "in",
    "ft": "ft",
    "foot": "ft",
    "feet": "ft",
    "yd": "yd",
    "yard": "yd",
    "yards": "yd",
    "mi": "mi",
    "mile": "mi",
    "miles": "mi",
    "nmi": "nmi",
    "nauticalmile": "nmi",
    "nauticalmiles": "nmi",
}

WEIGHT_FACTORS = {
    "mg": 0.000001,
    "g": 0.001,
    "kg": 1.0,
    "t": 1000.0,
    "lb": 0.45359237,
    "oz": 0.028349523125,
}
WEIGHT_ALIASES = {
    "mg": "mg",
    "milligram": "mg",
    "milligrams": "mg",
    "g": "g",
    "gram": "g",
    "grams": "g",
    "kg": "kg",
    "kilogram": "kg",
    "kilograms": "kg",
    "kilo": "kg",
    "kilos": "kg",
    "t": "t",
    "tonne": "t",
    "tonnes": "t",
    "ton": "t",
    "tons": "t",
    "lb": "lb",
    "lbs": "lb",
    "oz": "oz",
    "ounce": "oz",
    "ounces": "oz",
}

VOLUME_FACTORS = {
    "ml": 0.001,
    "cl": 0.01,
    "l": 1.0,
    "gal": 3.785411784,
    "qt": 0.946352946,
    "pt": 0.473176473,
    "cup": 0.24,
    "floz": 0.0295735296,
    "tbsp": 0.0147867648,
    "tsp": 0.00492892159,
}
VOLUME_ALIASES = {
    "ml": "ml",
    "milliliter": "ml",
    "milliliters": "ml",
    "millilitre": "ml",
    "millilitres": "ml",
    "cl": "cl",
    "centiliter": "cl",
    "centiliters": "cl",
    "l": "l",
    "liter": "l",
    "liters": "l",
    "litre": "l",
    "litres": "l",
    "gal": "gal",
    "gallon": "gal",
    "gallons": "gal",
    "qt": "qt",
    "quart": "qt",
    "quarts": "qt",
    "pt": "pt",
    "pint": "pt",
    "pints": "pt",
    "cup": "cup",
    "cups": "cup",
    "floz": "floz",
    "tbsp": "tbsp",
    "tablespoon": "tbsp",
    "tablespoons": "tbsp",
    "tsp": "tsp",
    "teaspoon": "tsp",
    "teaspoons": "tsp",
}

TIME_FACTORS = {
    "s": 1.0,
    "min": 60.0,
    "h": 3600.0,
    "day": 86400.0,
    "week": 604800.0,
    "month": 2629800.0,
    "year": 31557600.0,
}
TIME_ALIASES = {
    "s": "s",
    "sec": "s",
    "secs": "s",
    "second": "s",
    "seconds": "s",
    "min": "min",
    "mins": "min",
    "minute": "min",
    "minutes": "min",
    "h": "h",
    "hr": "h",
    "hrs": "h",
    "hour": "h",
    "hours": "h",
    "day": "day",
    "days": "day",
    "week": "week",
    "weeks": "week",
    "month": "month",
    "months": "month",
    "year": "year",
    "years": "year",
    "yr": "year",
    "yrs": "year",
}

DATA_FACTORS = {
    "b": 1.0,
    "kb": 1000.0,
    "mb": 1e6,
    "gb": 1e9,
    "tb": 1e12,
    "pb": 1e15,
    "kib": 1024.0,
    "mib": 1024.0**2,
    "gib": 1024.0**3,
    "tib": 1024.0**4,
}
DATA_ALIASES = {
    "b": "b",
    "byte": "b",
    "bytes": "b",
    "kb": "kb",
    "mb": "mb",
    "gb": "gb",
    "tb": "tb",
    "pb": "pb",
    "kib": "kib",
    "mib": "mib",
    "gib": "gib",
    "tib": "tib",
}

UNIT_TABLES = {
    "length": {"aliases": LENGTH_ALIASES, "factors": LENGTH_FACTORS},
    "weight": {"aliases": WEIGHT_ALIASES, "factors": WEIGHT_FACTORS},
    "volume": {"aliases": VOLUME_ALIASES, "factors": VOLUME_FACTORS},
    "time": {"aliases": TIME_ALIASES, "factors": TIME_FACTORS},
    "data": {"aliases": DATA_ALIASES, "factors": DATA_FACTORS},
}

TEMP_ALIASES = {
    "c": "c",
    "celsius": "c",
    "f": "f",
    "fahrenheit": "f",
    "k": "k",
    "kelvin": "k",
}

CURRENCY_ALIASES = {
    "usd": "USD",
    "dollar": "USD",
    "dollars": "USD",
    "usdollar": "USD",
    "buck": "USD",
    "bucks": "USD",
    "eur": "EUR",
    "euro": "EUR",
    "euros": "EUR",
    "ron": "RON",
    "lei": "RON",
    "leu": "RON",
    "gbp": "GBP",
    "quid": "GBP",
    "jpy": "JPY",
    "yen": "JPY",
    "chf": "CHF",
    "franc": "CHF",
    "francs": "CHF",
    "cad": "CAD",
    "aud": "AUD",
    "nzd": "NZD",
    "cny": "CNY",
    "yuan": "CNY",
    "rmb": "CNY",
    "inr": "INR",
    "rupee": "INR",
    "rupees": "INR",
    "try": "TRY",
    "lira": "TRY",
    "pln": "PLN",
    "zloty": "PLN",
    "huf": "HUF",
    "forint": "HUF",
    "czk": "CZK",
    "koruna": "CZK",
    "sek": "SEK",
    "nok": "NOK",
    "dkk": "DKK",
    "brl": "BRL",
    "real": "BRL",
    "reais": "BRL",
    "mxn": "MXN",
    "peso": "MXN",
    "pesos": "MXN",
    "zar": "ZAR",
    "rand": "ZAR",
    "krw": "KRW",
    "won": "KRW",
    "sgd": "SGD",
    "hkd": "HKD",
    "thb": "THB",
    "baht": "THB",
    "idr": "IDR",
    "rupiah": "IDR",
    "php": "PHP",
    "myr": "MYR",
    "ringgit": "MYR",
    "ils": "ILS",
    "shekel": "ILS",
    "bgn": "BGN",
    "isk": "ISK",
}

# Approximate fallback rates (base USD), used only if a live fetch has
# never succeeded and no cache file exists yet. Clearly marked as such
# wherever they're surfaced to the user.
FALLBACK_RATES = {
    "USD": 1.0,
    "EUR": 0.92,
    "RON": 4.58,
    "GBP": 0.79,
    "JPY": 149.5,
    "CHF": 0.88,
    "CAD": 1.36,
    "AUD": 1.52,
    "NZD": 1.64,
    "CNY": 7.24,
    "INR": 83.4,
    "TRY": 32.9,
    "PLN": 4.02,
    "HUF": 356.0,
    "CZK": 22.9,
    "SEK": 10.4,
    "NOK": 10.6,
    "DKK": 6.86,
    "BRL": 4.97,
    "MXN": 17.0,
    "ZAR": 18.7,
    "KRW": 1330.0,
    "SGD": 1.34,
    "HKD": 7.82,
    "THB": 35.5,
    "IDR": 15700.0,
    "PHP": 56.0,
    "MYR": 4.47,
    "ILS": 3.7,
    "BGN": 1.80,
    "ISK": 138.0,
}


def classify_token(tok):
    """Return (kind, canonical_unit) for a unit/currency word, or None."""
    t = tok.lower()
    if t in CURRENCY_ALIASES:
        return ("currency", CURRENCY_ALIASES[t])
    if t in TEMP_ALIASES:
        return ("temperature", TEMP_ALIASES[t])
    for cat, table in UNIT_TABLES.items():
        if t in table["aliases"]:
            return (cat, table["aliases"][t])
    return None


def unit_display(unit, kind):
    if kind == "currency":
        return unit
    if kind == "temperature":
        return {"c": "°C", "f": "°F", "k": "K"}.get(unit, unit)
    return unit


def _to_celsius(v, u):
    if u == "c":
        return v
    if u == "f":
        return (v - 32) * 5.0 / 9.0
    return v - 273.15  # kelvin


def _from_celsius(c, u):
    if u == "c":
        return c
    if u == "f":
        return c * 9.0 / 5.0 + 32
    return c + 273.15  # kelvin


# --------------------------------------------------------------------------
# Currency rates: fetched live (Frankfurter/ECB), cached to disk, with a
# graceful fallback chain: fresh fetch -> disk cache -> hard-coded table.
# --------------------------------------------------------------------------

PLUGIN_DIR = os.path.dirname(os.path.abspath(__file__))
RATES_CACHE_FILE = os.path.join(PLUGIN_DIR, "rates_cache.json")
RATES_TTL_SECONDS = 6 * 3600

RATES_STATE = {"rates": None, "ts": 0, "date": None, "stale": False, "error": None}


def _load_rates_cache():
    try:
        with open(RATES_CACHE_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def _save_rates_cache(data):
    try:
        with open(RATES_CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f)
    except Exception:
        pass


def _fetch_rates_live():
    url = "https://api.frankfurter.dev/v1/latest?from=USD"
    req = urllib.request.Request(
        url, headers={"User-Agent": "tabame-calculator-plugin"}
    )
    with urllib.request.urlopen(req, timeout=4) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    rates = dict(data.get("rates", {}))
    rates["USD"] = 1.0
    return {"rates": rates, "ts": time.time(), "date": data.get("date")}


def get_rates(force=False):
    """Returns {ISO_CODE: rate_vs_usd}. Lazily fetches/caches on demand."""
    now = time.time()
    if (
        not force
        and RATES_STATE["rates"]
        and (now - RATES_STATE["ts"] < RATES_TTL_SECONDS)
    ):
        return RATES_STATE["rates"]

    cache = None if force else _load_rates_cache()
    if cache and (now - cache.get("ts", 0) < RATES_TTL_SECONDS):
        RATES_STATE.update(cache)
        RATES_STATE["stale"] = False
        return RATES_STATE["rates"]

    try:
        fresh = _fetch_rates_live()
        _save_rates_cache(fresh)
        RATES_STATE.update(fresh)
        RATES_STATE["stale"] = False
        RATES_STATE["error"] = None
        return RATES_STATE["rates"]
    except Exception as e:
        fallback_cache = cache or _load_rates_cache()
        if fallback_cache and fallback_cache.get("rates"):
            RATES_STATE.update(fallback_cache)
            RATES_STATE["stale"] = True
            RATES_STATE["error"] = str(e)
            return RATES_STATE["rates"]
        if RATES_STATE.get("rates"):
            RATES_STATE["stale"] = True
            RATES_STATE["error"] = str(e)
            return RATES_STATE["rates"]
        RATES_STATE.update(
            {"rates": FALLBACK_RATES, "ts": now, "date": "fallback (approximate)"}
        )
        RATES_STATE["stale"] = True
        RATES_STATE["error"] = str(e)
        return RATES_STATE["rates"]


# --------------------------------------------------------------------------
# Expression parsing & evaluation
# --------------------------------------------------------------------------


class CalcError(Exception):
    pass


class Value:
    __slots__ = ("number", "unit", "kind")

    def __init__(self, number, unit=None, kind=None):
        self.number = number
        self.unit = unit
        self.kind = kind


class Tok:
    __slots__ = ("type", "text")

    def __init__(self, t, x):
        self.type = t
        self.text = x


TOKEN_PATTERN = re.compile(
    r"""
    (?P<NUM>\d+\.\d+(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?|\d+(?:[eE][+-]?\d+)?)
  | (?P<VAR>\$[A-Za-z]+)
  | (?P<IDENT>[A-Za-z]+)
  | (?P<OP>[()+\-*/^%!,])
""",
    re.VERBOSE,
)


def tokenize(s):
    toks = []
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if c.isspace():
            i += 1
            continue
        m = TOKEN_PATTERN.match(s, i)
        if not m:
            raise CalcError(f"Unexpected character '{c}'")
        i = m.end()
        toks.append(Tok(m.lastgroup, m.group()))
    return toks


FUNCTIONS = {
    "sqrt": math.sqrt,
    "cbrt": lambda a: math.copysign(abs(a) ** (1.0 / 3.0), a),
    "abs": abs,
    "ln": math.log,
    "log": math.log10,
    "log2": math.log2,
    "exp": math.exp,
    "sin": lambda a: math.sin(math.radians(a)),
    "cos": lambda a: math.cos(math.radians(a)),
    "tan": lambda a: math.tan(math.radians(a)),
    "asin": lambda a: math.degrees(math.asin(a)),
    "acos": lambda a: math.degrees(math.acos(a)),
    "atan": lambda a: math.degrees(math.atan(a)),
    "sinh": math.sinh,
    "cosh": math.cosh,
    "tanh": math.tanh,
    "floor": math.floor,
    "ceil": math.ceil,
    "round": round,
}
MULTI_ARG_FUNCTIONS = {
    "min": lambda *a: min(a),
    "max": lambda *a: max(a),
    "pow": lambda a, b: a**b,
    "mod": math.fmod,
    "logb": lambda a, b: math.log(a, b),
}
CONSTANTS = {"pi": math.pi, "e": math.e}


class Parser:
    def __init__(self, text, rates_getter, variables=None):
        self.toks = tokenize(text)
        self.pos = 0
        self.rates_getter = rates_getter
        if callable(variables):
            self.variable_getter = variables
        else:
            variable_map = variables or {}
            self.variable_getter = lambda name: variable_map.get(name)
        self.trace = []

    def peek(self):
        return self.toks[self.pos] if self.pos < len(self.toks) else None

    def peek2(self):
        return self.toks[self.pos + 1] if self.pos + 1 < len(self.toks) else None

    def advance(self):
        t = self.peek()
        if t is None:
            raise CalcError("Unexpected end of expression")
        self.pos += 1
        return t

    def expect_op(self, ch):
        t = self.peek()
        if t is None or t.type != "OP" or t.text != ch:
            raise CalcError(f"Expected '{ch}'")
        self.pos += 1

    def parse(self):
        val = self.parse_clause()
        if self.peek() is not None:
            raise CalcError(f"Unexpected '{self.peek().text}'")
        return val

    # A "clause" is a full additive expression optionally tagged with a
    # unit/currency and optionally converted via one or more "to X".
    def parse_clause(self):
        val = self.parse_additive()
        t = self.peek()
        if (
            t
            and t.type == "IDENT"
            and t.text.lower() != "to"
            and classify_token(t.text) is not None
        ):
            tok = self.advance().text
            val = self.attach_unit(val, tok)
        while True:
            t = self.peek()
            if t and t.type == "IDENT" and t.text.lower() == "to":
                self.advance()
                t2 = self.peek()
                if not t2 or t2.type != "IDENT":
                    raise CalcError("Expected a unit after 'to'")
                target = self.advance().text
                val = self.convert_value(val, target)
            else:
                break
        return val

    def parse_additive(self):
        val = self.parse_mult()
        while True:
            t = self.peek()
            if t and t.type == "OP" and t.text in ("+", "-"):
                op = self.advance().text
                rhs = self.parse_mult()
                val = self.add_value(val, rhs, 1 if op == "+" else -1)
            else:
                break
        return val

    def parse_mult(self):
        val = self.parse_unary()
        while True:
            t = self.peek()
            if t and t.type == "OP" and t.text in ("*", "/"):
                op = self.advance().text
                rhs = self.parse_unary()
                val = (
                    self.mul_value(val, rhs) if op == "*" else self.div_value(val, rhs)
                )
            else:
                break
        return val

    def parse_unary(self):
        t = self.peek()
        if t and t.type == "OP" and t.text == "-":
            self.advance()
            v = self.parse_unary()
            return Value(-v.number, v.unit, v.kind)
        if t and t.type == "OP" and t.text == "+":
            self.advance()
            return self.parse_unary()
        return self.parse_pow()

    def parse_pow(self):
        val = self.parse_postfix()
        t = self.peek()
        if t and t.type == "OP" and t.text == "^":
            self.advance()
            rhs = self.parse_unary()
            val = self.pow_value(val, rhs)
        return val

    def parse_postfix(self):
        val = self.parse_primary()
        while True:
            t = self.peek()
            if t and t.type == "OP" and t.text == "%":
                self.advance()
                val = Value(val.number / 100.0, val.unit, val.kind)
            elif t and t.type == "OP" and t.text == "!":
                self.advance()
                if val.number < 0 or val.number != int(val.number) or val.number > 170:
                    raise CalcError("Factorial needs a non-negative integer ≤ 170")
                val = Value(float(math.factorial(int(val.number))), None, None)
            else:
                break
        return val

    def parse_primary(self):
        t = self.peek()
        if t is None:
            raise CalcError("Unexpected end of expression")
        if t.type == "NUM":
            self.advance()
            return Value(float(t.text), None, None)
        if t.type == "OP" and t.text == "(":
            self.advance()
            val = self.parse_clause()
            self.expect_op(")")
            return val
        if t.type == "VAR":
            self.advance()
            name = t.text[1:].lower()
            value = self.variable_getter(name)
            if value is None:
                raise CalcError(f"Unknown variable '{t.text}'")
            return Value(value.number, value.unit, value.kind)
        if t.type == "IDENT":
            name = t.text.lower()
            nxt = self.peek2()
            if (
                nxt
                and nxt.type == "OP"
                and nxt.text == "("
                and (name in FUNCTIONS or name in MULTI_ARG_FUNCTIONS)
            ):
                self.advance()
                self.advance()
                args = [self.parse_clause().number]
                while True:
                    t2 = self.peek()
                    if t2 and t2.type == "OP" and t2.text == ",":
                        self.advance()
                        args.append(self.parse_clause().number)
                    else:
                        break
                self.expect_op(")")
                if name in FUNCTIONS:
                    if len(args) != 1:
                        raise CalcError(f"{name}() takes exactly 1 argument")
                    try:
                        r = FUNCTIONS[name](args[0])
                    except (ValueError, OverflowError):
                        raise CalcError(f"Invalid input for {name}()")
                    return Value(float(r), None, None)
                else:
                    try:
                        r = MULTI_ARG_FUNCTIONS[name](*args)
                    except Exception:
                        raise CalcError(f"Invalid arguments for {name}()")
                    return Value(float(r), None, None)
            if name in CONSTANTS:
                self.advance()
                return Value(CONSTANTS[name], None, None)
            raise CalcError(f"Unknown identifier '{t.text}'")
        raise CalcError(f"Unexpected token '{t.text}'")

    # -- unit-aware operations --------------------------------------------

    def attach_unit(self, val, tok):
        cls = classify_token(tok)
        if cls is None:
            raise CalcError(f"Unknown unit '{tok}'")
        kind, canon = cls
        if val.unit is not None:
            if val.kind == kind and val.unit == canon:
                return val
            raise CalcError(
                f"'{val.unit}' is already applied; can't also tag as '{canon}'"
            )
        return Value(val.number, canon, kind)

    def convert_value(self, val, target_tok):
        cls = classify_token(target_tok)
        if cls is None:
            raise CalcError(f"Unknown unit '{target_tok}'")
        kind, canon = cls
        if val.unit is None:
            raise CalcError(f"Nothing to convert — put a unit before 'to {target_tok}'")
        if kind != val.kind:
            raise CalcError(
                f"Can't convert {unit_display(val.unit, val.kind)} to {unit_display(canon, kind)} (different categories)"
            )
        if kind == "currency":
            rates = self.rates_getter()
            if val.unit not in rates:
                raise CalcError(
                    f"Currency '{val.unit}' isn't supported by the rate provider"
                )
            if canon not in rates:
                raise CalcError(
                    f"Currency '{canon}' isn't supported by the rate provider"
                )
            usd = val.number / rates[val.unit]
            result = usd * rates[canon]
            rate = rates[canon] / rates[val.unit]
            self.trace.append(f"1 {val.unit} = {fmt_plain(rate)} {canon}")
            return Value(result, canon, "currency")
        if kind == "temperature":
            c = _to_celsius(val.number, val.unit)
            result = _from_celsius(c, canon)
            self.trace.append(
                f"{fmt_plain(val.number)}{unit_display(val.unit, kind)} = {fmt_plain(result)}{unit_display(canon, kind)}"
            )
            return Value(result, canon, "temperature")
        table = UNIT_TABLES[kind]["factors"]
        base = val.number * table[val.unit]
        result = base / table[canon]
        self.trace.append(
            f"1 {val.unit} = {fmt_plain(table[val.unit] / table[canon])} {canon}"
        )
        return Value(result, canon, kind)

    def add_value(self, a, b, sign):
        if a.unit and b.unit:
            if a.kind != b.kind:
                raise CalcError(
                    f"Can't combine {unit_display(a.unit, a.kind)} and {unit_display(b.unit, b.kind)}"
                )
            if a.unit != b.unit:
                b = self.convert_value(b, a.unit)
            return Value(a.number + sign * b.number, a.unit, a.kind)
        if a.unit:
            return Value(a.number + sign * b.number, a.unit, a.kind)
        if b.unit:
            return Value(a.number + sign * b.number, b.unit, b.kind)
        return Value(a.number + sign * b.number, None, None)

    def mul_value(self, a, b):
        if a.unit and b.unit:
            raise CalcError(
                f"Can't multiply {unit_display(a.unit, a.kind)} by {unit_display(b.unit, b.kind)}"
            )
        return Value(a.number * b.number, a.unit or b.unit, a.kind or b.kind)

    def div_value(self, a, b):
        if b.number == 0:
            raise CalcError("Division by zero")
        if a.unit and b.unit:
            if a.kind == b.kind:
                bb = self.convert_value(b, a.unit) if a.unit != b.unit else b
                return Value(a.number / bb.number, None, None)
            raise CalcError(
                f"Can't divide {unit_display(a.unit, a.kind)} by {unit_display(b.unit, b.kind)}"
            )
        return Value(a.number / b.number, a.unit, a.kind)

    def pow_value(self, a, b):
        if b.unit:
            raise CalcError("Exponent can't have a unit")
        try:
            r = a.number**b.number
        except (OverflowError, ValueError):
            raise CalcError("Result is too large")
        unit = a.unit if (a.unit and b.number == 1) else None
        kind = a.kind if unit else None
        return Value(r, unit, kind)


def evaluate(text, rates_getter, variables=None):
    parser = Parser(text, rates_getter, variables)
    val = parser.parse()
    return val, parser.trace


# --------------------------------------------------------------------------
# Formatting
# --------------------------------------------------------------------------


def fmt_plain(x):
    if x is None:
        return "?"
    ax = abs(x)
    if ax != 0 and (ax < 1e-6 or ax >= 1e12):
        return f"{x:.6g}"
    r = round(x, 6)
    if r == int(r):
        return str(int(r))
    s = f"{r:.6f}".rstrip("0").rstrip(".")
    return s


def fmt_number(x):
    if x is None:
        return "?"
    ax = abs(x)
    if ax != 0 and (ax < 1e-6 or ax >= 1e15):
        return f"{x:.6g}"
    r = round(x, 6)
    if r == int(r):
        return f"{int(r):,}"
    s = f"{r:,.6f}".rstrip("0").rstrip(".")
    return s


def format_value(val):
    n = fmt_number(val.number)
    if val.unit:
        return f"{n} {unit_display(val.unit, val.kind)}"
    return n


def icon_for_kind(kind):
    if kind == "currency":
        return "money"
    if kind == "temperature":
        return "weather"
    return "calculator"


def relative_time(ts):
    d = time.time() - ts
    if d < 60:
        return "just now"
    if d < 3600:
        return f"{int(d // 60)}m ago"
    if d < 86400:
        return f"{int(d // 3600)}h ago"
    return f"{int(d // 86400)}d ago"


# --------------------------------------------------------------------------
# Plugin state
# --------------------------------------------------------------------------

history = []
history_loaded = False
variables = []
variables_loaded = False
current_text = ""
editing_variable = None
_hist_seq = 0

EXAMPLES = [
    "(10 * 30% usd to ron) + 30",
    "15 km to mi",
    "45 c to f",
    "sqrt(144) + 3^2",
    "200 usd to eur",
    "2.5 kg to lb",
]


def add_history(expr, display):
    global _hist_seq
    _hist_seq += 1
    history.append(
        {"id": _hist_seq, "expr": expr, "display": display, "ts": time.time()}
    )
    if len(history) > 50:
        del history[0 : len(history) - 50]
    save_history()


def save_history():
    send(
        {
            "type": "command",
            "command": "storage",
            "op": "set",
            "key": "history",
            "value": json.dumps(history),
        }
    )


def serialize_value(value):
    return {
        "number": value.number,
        "unit": value.unit,
        "kind": value.kind,
        "display": format_value(value),
    }


def value_from_variable(entry):
    number = entry.get("number")
    if isinstance(number, bool) or not isinstance(number, (int, float)):
        return None
    return Value(float(number), entry.get("unit"), entry.get("kind"))


def normalize_variable(raw):
    if not isinstance(raw, dict):
        return None
    name = str(raw.get("name", "")).strip().lower().lstrip("$")
    formula = str(raw.get("formula", raw.get("expr", ""))).strip()
    value = value_from_variable(raw)
    timestamp = raw.get("ts", time.time())
    if isinstance(timestamp, bool) or not isinstance(timestamp, (int, float)):
        timestamp = time.time()
    if not name or not re.fullmatch(r"[a-z]+", name) or not formula or value is None:
        return None
    return {
        "name": name,
        "formula": formula,
        **serialize_value(value),
        "ts": timestamp,
    }


def variable_map():
    result = {}
    for entry in variables:
        value = value_from_variable(entry)
        if value is not None:
            result[entry["name"]] = value
    return result


def recalculate_variable_records(records):
    """Re-evaluate formulas in dependency order and update their saved values."""
    by_name = {entry["name"]: entry for entry in records}
    cache = {}
    resolving = []

    def resolve(name):
        name = name.lower()
        if name in cache:
            return cache[name]
        entry = by_name.get(name)
        if entry is None:
            raise CalcError(f"Unknown variable '${name}'")
        if name in resolving:
            cycle = " -> ".join(f"${part}" for part in resolving + [name])
            raise CalcError(f"Circular variable reference: {cycle}")
        resolving.append(name)
        try:
            value, _trace = evaluate(entry["formula"], get_rates, resolve)
        finally:
            resolving.pop()
        cache[name] = value
        entry.update(serialize_value(value))
        return value

    for entry in records:
        resolve(entry["name"])
    return cache


def variable_label(index):
    """Return spreadsheet-style lowercase labels: a, b, ..., z, aa, ab."""
    label = ""
    while True:
        label = chr(ord("a") + index % 26) + label
        index = index // 26 - 1
        if index < 0:
            return label


def next_variable_name():
    used = {entry["name"] for entry in variables}
    index = 0
    while variable_label(index) in used:
        index += 1
    return variable_label(index)


def save_variables():
    send(
        {
            "type": "command",
            "command": "storage",
            "op": "set",
            "key": "variables",
            "value": json.dumps(variables, ensure_ascii=False),
        }
    )


def add_variable(formula, value):
    entry = {
        "name": next_variable_name(),
        "formula": formula.strip(),
        **serialize_value(value),
        "ts": time.time(),
    }
    variables.append(entry)
    save_variables()
    return entry


def history_items():
    items = []
    for h in reversed(history[-30:]):
        items.append(
            {
                "id": f"h{h['id']}",
                "title": f"**{h['display']}**",
                "subtitle": h["expr"],
                "icon": "clock",
                "section": "History",
                "accessories": [{"text": relative_time(h["ts"])}],
                "actions": [
                    {"id": "reuse", "title": "Reuse Expression", "icon": "edit"},
                    {"id": "copy", "title": "Copy Result", "icon": "copy"},
                    {
                        "id": "delete",
                        "title": "Remove",
                        "icon": "trash",
                        "destructive": True,
                    },
                ],
                "preview": {"markdown": f"### {h['expr']}\n\n**= {h['display']}**"},
            }
        )
    return items


def variable_preview(entry, value):
    return (
        f"### ${entry['name']}\n\n"
        f"**Formula**\n\n`{entry['formula']}`\n\n"
        f"**Value**\n\n= {format_value(value)}\n\n"
        "Use this value in a calculation as `$"
        f"{entry['name']}`. Choose **Edit Formula** to update it."
    )


def variable_items():
    items = []
    for entry in reversed(variables):
        value = value_from_variable(entry)
        if value is None:
            continue
        items.append(
            {
                "id": f"v:{entry['name']}",
                "title": f"**${entry['name']} = {format_value(value)}**",
                "subtitle": entry["formula"],
                "icon": icon_for_kind(value.kind),
                "section": "Variables",
                "lines": 2,
                "accessories": [{"text": "variable", "color": "#8B5CF6"}],
                "actions": [
                    {"id": "edit", "title": "Edit Formula", "icon": "edit"},
                    {"id": "use", "title": "Use in Expression", "icon": "calculator"},
                    {"id": "copy", "title": "Copy Value", "icon": "copy"},
                ],
                "preview": {
                    "markdown": variable_preview(entry, value),
                    "metadata": [
                        {"label": "Variable", "text": f"${entry['name']}"},
                        {"label": "Formula", "text": entry["formula"]},
                        {"label": "Value", "text": format_value(value)},
                    ],
                },
            }
        )
    return items


def example_items():
    items = []
    for ex in EXAMPLES:
        items.append(
            {
                "id": f"ex:{ex}",
                "title": ex,
                "subtitle": "Tap to try this example",
                "icon": "bolt",
                "section": "Examples",
                "actions": [{"id": "use", "title": "Use Example", "icon": "edit"}],
            }
        )
    return items


def frame_actions():
    acts = [
        {"id": "refresh_rates", "title": "Refresh Currency Rates", "icon": "refresh"}
    ]
    if variables:
        acts.append(
            {
                "id": "clear_variables",
                "title": "Clear Variables",
                "icon": "trash",
                "destructive": True,
                "shortcut": "CTRL+SHIFT+C",
                "confirm": {
                    "title": "Clear saved variables?",
                    "message": "All variable formulas and values will be removed.",
                    "confirmLabel": "Clear",
                },
            }
        )
    if history:
        acts.append(
            {
                "id": "clear_history",
                "title": "Clear History",
                "icon": "trash",
                "destructive": True,
                "shortcut": "CTRL+SHIFT+H",
                "confirm": {
                    "title": "Clear calculation history?",
                    "message": "This cannot be undone.",
                    "confirmLabel": "Clear",
                },
            }
        )
    return acts


def build_breakdown_md(text, val, trace):
    lines = [f"### {text}", "", f"**= {format_value(val)}**", ""]
    if trace:
        lines.append("**Conversion steps**")
        for step in trace:
            lines.append(f"- {step}")
    else:
        lines.append("_Straightforward arithmetic — no conversions applied._")
    return "\n".join(lines)


def build_metadata(val, trace):
    meta = [{"label": "Result", "text": format_value(val)}]
    if val.kind == "currency":
        source = (
            "Frankfurter (ECB rates)"
            if not RATES_STATE.get("stale")
            else "Cached / fallback rates"
        )
        meta.append({"label": "Rate source", "text": source, "icon": "info"})
        meta.append(
            {"label": "Rates as of", "text": str(RATES_STATE.get("date") or "—")}
        )
    if trace:
        meta.append({"separator": True})
        for step in trace:
            meta.append({"label": "Step", "text": step})
    return meta


def find_variable(name):
    name = name.lower().lstrip("$")
    return next((entry for entry in variables if entry["name"] == name), None)


def render_variable_form(name, rev=0, error=None, formula=None):
    entry = find_variable(name)
    if entry is None:
        render(rev, current_text)
        return
    form = {
        "title": f"Edit ${entry['name']}",
        "submitLabel": "Save Formula",
        "buttons": [
            {"id": "save", "label": "Save Formula"},
            {"id": "cancel", "label": "Cancel"},
        ],
        "fields": [
            {
                "id": "formula",
                "type": "text",
                "label": "Formula",
                "value": formula if formula is not None else entry["formula"],
                "required": True,
                "description": "Use earlier variables such as $a or $b. The value is recalculated on save.",
            },
        ],
    }
    if error:
        form["error"] = error
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "form",
            "canGoBack": True,
            "placeholder": f"Edit ${entry['name']} formula",
            "form": form,
        }
    )


def render(rev, text, select_id=None):
    text = (text or "").strip()

    if not text:
        frame = {
            "type": "render",
            "rev": rev,
            "view": "list",
            "placeholder": "Type a calculation… e.g. (10 * 30% usd to ron) + 30",
            "empty": {
                "icon": "calculator",
                "title": "Professional Calculator",
                "hint": "Extended math, currency & unit conversion — try an example below",
            },
            "items": variable_items()
            if variables
            else example_items() + history_items(),
            "actions": frame_actions(),
        }
        frame["placeholder"] = "Type a calculation (use $a, $b from saved variables)"
        frame["empty"]["hint"] = (
            "Press Enter on a result to save $a, $b, $c...; use them in later formulas"
        )
        # frame["preview"] = {"enabled": True, "wide": True}
        if select_id:
            frame["selectId"] = select_id
        send(frame)
        return

    try:
        val, trace = evaluate(text, get_rates, variable_map())
        display = format_value(val)
        result_item = {
            "id": "result",
            "title": f"**{display}**",
            "subtitle": f"= {text}",
            "icon": icon_for_kind(val.kind),
            "accessories": [
                {
                    "text": unit_display(val.unit, val.kind),
                    "color": "#10B981" if val.kind == "currency" else "#6366F1",
                }
            ]
            if val.unit
            else [],
            "actions": [
                {
                    "id": "save_variable",
                    "title": "Save as Next Variable",
                    "icon": "check",
                },
                {"id": "copy", "title": "Copy Result", "icon": "copy"},
                {"id": "copy_line", "title": "Copy Full Line", "icon": "content_copy"},
            ],
            "preview": {
                "markdown": build_breakdown_md(text, val, trace),
                "metadata": build_metadata(val, trace),
            },
        }
        send(
            {
                "type": "render",
                "rev": rev,
                "view": "list",
                # "preview": {"enabled": True, "wide": True},
                "placeholder": "Type a calculation (use $a, $b from saved variables)",
                "selectId": "result",
                "items": [result_item] + variable_items(),
                "actions": frame_actions(),
            }
        )
    except CalcError as e:
        send(
            {
                "type": "render",
                "rev": rev,
                "view": "list",
                # "preview": {"enabled": True, "wide": True},
                "placeholder": "Type a calculation (use $a, $b from saved variables)",
                "items": [
                    {
                        "id": "error",
                        "title": "Invalid expression",
                        "subtitle": str(e),
                        "icon": "warning",
                        "accessories": [{"text": "Error", "color": "#EF4444"}],
                    }
                ]
                + variable_items(),
                "actions": frame_actions(),
            }
        )


def handle_action(msg):
    global current_text, editing_variable
    item_id = msg.get("id", "") or ""
    action = msg.get("action", "default")

    if item_id == "result":
        try:
            val, _trace = evaluate(current_text, get_rates, variable_map())
        except CalcError:
            return
        display = format_value(val)
        if action in ("default", "save_variable"):
            entry = add_variable(current_text, val)
            add_history(current_text, display)
            send(
                {
                    "type": "command",
                    "command": "toast",
                    "text": f"Saved ${entry['name']} = {display}",
                    "style": "success",
                }
            )
            current_text = ""
            render(0, "", select_id=f"v:{entry['name']}")
            send({"type": "command", "command": "setQuery", "text": " "})
        elif action == "copy":
            send({"type": "command", "command": "copy", "text": format_value(val)})
            send({"type": "command", "command": "toast", "text": "Copied to clipboard"})
        elif action == "copy_line":
            send(
                {
                    "type": "command",
                    "command": "copy",
                    "text": f"{current_text} = {display}",
                }
            )
            send({"type": "command", "command": "toast", "text": "Copied"})
        return

    if item_id.startswith("v:"):
        name = item_id[2:].lower()
        entry = find_variable(name)
        if entry is None:
            render(0, current_text)
            return
        value = value_from_variable(entry)
        if action in ("default", "edit"):
            editing_variable = name
            render_variable_form(name)
        elif action == "use":
            current_text = f"${name}"
            send({"type": "command", "command": "setQuery", "text": current_text})
        elif action == "copy" and value is not None:
            send({"type": "command", "command": "copy", "text": format_value(value)})
            send({"type": "command", "command": "toast", "text": "Copied"})
        return

    if item_id.startswith("h"):
        hid = item_id[1:]
        entry = next((h for h in history if str(h["id"]) == hid), None)
        if not entry:
            render(0, current_text)
            return
        if action in ("default", "reuse"):
            send({"type": "command", "command": "setQuery", "text": entry["expr"]})
        elif action == "copy":
            send({"type": "command", "command": "copy", "text": entry["display"]})
            send({"type": "command", "command": "toast", "text": "Copied"})
        elif action == "delete":
            history[:] = [h for h in history if str(h["id"]) != hid]
            save_history()
            render(0, current_text)
        return

    if item_id.startswith("ex:"):
        example_text = item_id[3:]
        send({"type": "command", "command": "setQuery", "text": example_text})
        return

    if item_id == "":
        if action == "refresh_rates":
            get_rates(force=True)
            ok = not RATES_STATE.get("stale")
            send(
                {
                    "type": "command",
                    "command": "toast",
                    "text": "Rates refreshed"
                    if ok
                    else "Refresh failed — using cached/fallback rates",
                    "style": "success" if ok else "error",
                }
            )
            render(0, current_text)
        elif action == "clear_variables":
            variables.clear()
            save_variables()
            send({"type": "command", "command": "toast", "text": "Variables cleared"})
            render(0, current_text)
        elif action == "clear_history":
            history.clear()
            save_history()
            render(0, current_text)
        return


def handle_form_submit(msg):
    global editing_variable
    if editing_variable is None:
        return
    button = msg.get("button", "save")
    if button == "cancel":
        editing_variable = None
        render(0, current_text)
        return

    values = msg.get("values", {})
    formula = str(values.get("formula", "")).strip()
    entry = find_variable(editing_variable)
    if entry is None:
        editing_variable = None
        render(0, current_text)
        return
    if not formula:
        render_variable_form(
            editing_variable, error="Enter a formula.", formula=formula
        )
        return

    candidate = [dict(item) for item in variables]
    candidate_entry = next(
        item for item in candidate if item["name"] == editing_variable
    )
    candidate_entry["formula"] = formula
    try:
        recalculate_variable_records(candidate)
    except CalcError as error:
        render_variable_form(editing_variable, error=str(error), formula=formula)
        return

    variables[:] = candidate
    save_variables()
    saved_name = editing_variable
    editing_variable = None
    updated = find_variable(saved_name)
    display = format_value(value_from_variable(updated)) if updated else "?"
    send(
        {
            "type": "command",
            "command": "toast",
            "text": f"Updated ${saved_name} = {display}",
            "style": "success",
        }
    )
    render(0, current_text, select_id=f"v:{saved_name}")


def handle_storage_reply(msg):
    global history_loaded, variables_loaded, _hist_seq
    request_id = msg.get("requestId")
    val = msg.get("value")
    if request_id == "hist_get":
        if val:
            try:
                loaded = json.loads(val)
                if isinstance(loaded, list):
                    history[:] = loaded
                    if history:
                        _hist_seq = max((h.get("id", 0) for h in history), default=0)
            except Exception:
                pass
        history_loaded = True
        render(0, current_text)
    elif request_id == "vars_get":
        if val:
            try:
                loaded = json.loads(val)
                if isinstance(loaded, list):
                    loaded_variables = []
                    for raw in loaded:
                        entry = normalize_variable(raw)
                        if entry is not None:
                            loaded_variables.append(entry)
                    variables[:] = loaded_variables
            except Exception:
                pass
        variables_loaded = True
        render(0, current_text)


def main():
    global current_text, editing_variable
    for raw in sys.stdin:
        raw = raw.strip()
        if not raw:
            continue
        try:
            msg = json.loads(raw)
        except json.JSONDecodeError:
            continue

        t = msg.get("type")
        if t == "close":
            break
        elif t == "init":
            current_text = msg.get("text", msg.get("query", ""))
            render(msg.get("rev", 0), current_text)
            send(
                {
                    "type": "command",
                    "command": "storage",
                    "op": "get",
                    "key": "history",
                    "requestId": "hist_get",
                }
            )
            send(
                {
                    "type": "command",
                    "command": "storage",
                    "op": "get",
                    "key": "variables",
                    "requestId": "vars_get",
                }
            )
        elif t == "query":
            current_text = msg.get("text", msg.get("query", ""))
            editing_variable = None
            render(msg.get("rev", 0), current_text)
        elif t == "submitQuery":
            current_text = msg.get("text", "")
            editing_variable = None
            render(msg.get("rev", 0), current_text)
        elif t == "action":
            handle_action(msg)
        elif t == "submit":
            handle_form_submit(msg)
        elif t == "storage":
            handle_storage_reply(msg)
        elif t == "back" and editing_variable is not None:
            editing_variable = None
            render(0, current_text)
        # select / tab / navigate are not used by this plugin


if __name__ == "__main__":
    main()
