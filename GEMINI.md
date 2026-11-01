# Smart-E HE Project Guidelines

## UI & Dropdown Components
- **Searchable Dropdowns**: Seluruh dropdown item pemilihan (seperti node target, daftar file peer/certificate, item konfigurasi) **wajib menggunakan `FuzzySearchableDropdown`** (dari `lib/widgets/fuzzy_searchable_dropdown.dart`) dan tidak menggunakan `DropdownButton` / `DropdownButtonFormField` biasa tanpa search bar.
- Ini memastikan pengguna dapat mencari item dengan cepat, akurat, dan memiliki fitur fuzzy search & highlighting yang flawless.
