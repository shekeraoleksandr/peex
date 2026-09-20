"""Tiny business logic module — the unit under test in the CI pipeline."""


def add(a, b):
    return a + b


def mul(a, b):
    return a * b


def discount(price, percent):
    if not 0 <= percent <= 100:
        raise ValueError("percent must be between 0 and 100")
    return round(price * (1 - percent / 100), 2)
