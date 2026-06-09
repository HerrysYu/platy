# Project Maya iOS

This repo is now wired to the Supabase project ``.

## What changed

- Auth now uses Supabase Auth
- Meal history syncs to the `meals` table
- User preferences save to the `profiles` table
- OCR translation and dish details call Supabase Edge Functions

## Local setup

1. Open `ProjectMayaIOS/ProjectMayaIOS.xcodeproj` in Xcode.
2. Provide these env values if you want to override defaults:
   - `SUPABASE_URL`
   - `SUPABASE_PUBLISHABLE_KEY`
3. For local Supabase work, the repo is already linked to the cloud project.

## Supabase notes

- Remote project ref: ``
- The migration baseline is in `supabase/migrations/`
- Edge Functions live in `supabase/functions/`

