# The frontend names permission GUIDs from a copy of backend/Config/PermissionsTranslator.json.
# build/tools/Update-PermissionsTranslator.ps1 writes both; this catches an edit to only one.

Describe 'PermissionsTranslator copies' {
    It 'frontend/public/permissionsTranslator.json matches backend/Config/PermissionsTranslator.json' {
        $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath)))
        $Backend = Join-Path $RepoRoot 'backend/Config/PermissionsTranslator.json'
        $Frontend = Join-Path $RepoRoot 'frontend/public/permissionsTranslator.json'

        (Get-FileHash -LiteralPath $Frontend).Hash | Should -Be (Get-FileHash -LiteralPath $Backend).Hash
    }
}
