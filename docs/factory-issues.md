# Writing an issue for the factory

The factory (`/factory run`, see `AGENTS.md`) builds GitHub issues labeled
`factory` with no human looking at the story or the spec. The only places a
human shapes the work are the issue and the final PR. Intake turns the issue
into a scope and the spec writer turns that into acceptance criteria, so
whatever the issue leaves open, an agent decides. Use the **Factory feature**
issue template, which asks for each part below.

## What a good issue has

1. **One concrete behaviour, not an area.** "Products" is too broad. "A
   `Product` model with name, slug, price and stock, plus its admin" is one
   reviewable pull request. If you have more, open more issues.
2. **Testable acceptance criteria.** For each behaviour: which endpoint (method
   and path), what input, what output, and which status code. Include the
   failure cases you care about (bad input, not found, not allowed).
3. **The product decisions only you can make.** Who may do this (anonymous,
   any signed-in user, the owner, staff with `is_admin`)? What is public? How
   is money calculated (currency, rounding, tax, discounts)? What happens to
   stock? An agent will guess anything you leave out.
4. **What is deliberately out of scope.** Name the tempting extras the builder
   must not add in this issue.
5. **Dependencies.** Write `Depends on #12` for every issue that must be merged
   first. The factory doesn't understand order, so **add the `factory` label
   only once every dependency is merged.**

## Example

> **Title:** Add the Product model and its admin
>
> **Behaviour:** A `products` app with a `Product` model (name, unique slug,
> price, stock) registered in the Django admin. No API yet.
>
> **Acceptance criteria**
> - `Product` has `name` (max 200), `slug` (unique), `price`
>   (`DecimalField`, 12 digits, 2 decimal places, `>= 0`) and `stock`
>   (`PositiveIntegerField`, default 0), and inherits `BaseModel`.
> - Saving a product with a negative price or a duplicate slug raises
>   `ValidationError`.
> - Staff can create, edit and search products by name and slug in `/admin/`.
> - Tests cover a valid product, a negative price and a duplicate slug.
>
> **Product decisions:** prices are in one currency (IRR), stored without
> tax. Only staff manage products.
>
> **Out of scope:** product API endpoints, categories, images, stock
> reservation.
>
> **Depends on:** none

## Before you add the label

- The behaviour fits in one PR, and every criterion can be checked by someone
  who only has the repo.
- Every product decision is written down, or marked "your choice" when you
  really don't mind.
- Every `Depends on #n` issue is closed by a merged PR.

If the issue is too vague, intake asks up to three questions on it and labels
it `factory:needs-info`. Answer them in a comment and the next `/factory run`
picks it up again.
