# Craft copies the first line after .ROLE into function-permissions.json and Get-Help returns the whole paragraph,
# so a role has to be one line of comma-separated permission names for both to agree.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:EntrypointRoot = Join-Path $BackendRoot 'Modules/CIPPHTTP/Public'

    function Get-RoleProblem([string]$Text) {
        $Name = '[A-Za-z0-9]+\.[A-Za-z0-9]+\.[A-Za-z]+'
        $Lines = $Text -split '\r?\n'
        for ($i = 0; $i -lt $Lines.Count; $i++) {
            if ($Lines[$i] -notmatch '^\s*\.ROLE\b') { continue }
            if ($Lines[$i] -notmatch '^\s*\.ROLE\s*$') { "'$($Lines[$i].Trim())' puts the role on the .ROLE line"; continue }
            $Value = "$($Lines[$i + 1])".Trim()
            $Next = "$($Lines[$i + 2])".Trim()
            if ($Value -notmatch "^(Public|$Name(\s*,\s*$Name)*)$") {
                "'$Value' is not a comma-separated list of permissions"
            } elseif ($Next -and $Next -notmatch '^(\.|#>)') {
                "'$Next' continues the role on another line"
            }
        }
    }
}

Describe 'HTTP entrypoint .ROLE' {
    It 'is one line of comma-separated permission names' {
        $Files = @(Get-ChildItem -Path $script:EntrypointRoot -Filter 'Invoke-*.ps1' -File -Recurse)
        $Files.Count | Should -BeGreaterThan 400

        $Offenders = foreach ($File in $Files) {
            foreach ($Problem in Get-RoleProblem (Get-Content -Path $File.FullName -Raw)) { "$($File.BaseName): $Problem" }
        }
        $Offenders | Should -BeNullOrEmpty
    }

    It 'accepts <Case>' -ForEach @(
        @{ Case = 'one permission'; Help = ".ROLE`n    Identity.User.ReadWrite`n#>" }
        @{ Case = 'a list'; Help = ".ROLE`n    Identity.User.ReadWrite, Identity.PrivilegedUser.ReadWrite`n.DESCRIPTION" }
        @{ Case = 'Public'; Help = ".ROLE`n    Public`n" }
    ) {
        Get-RoleProblem $Help | Should -BeNullOrEmpty
    }

    It 'rejects <Case>' -ForEach @(
        @{ Case = 'a list over two lines'; Help = ".ROLE`n    Identity.User.ReadWrite`n    Identity.PrivilegedUser.ReadWrite`n#>" }
        @{ Case = 'a semicolon list'; Help = ".ROLE`n    Identity.User.ReadWrite;Identity.PrivilegedUser.ReadWrite`n#>" }
        @{ Case = 'a role on the .ROLE line'; Help = ".ROLE Identity.User.ReadWrite`n#>" }
        @{ Case = 'a missing role'; Help = ".ROLE`n#>" }
    ) {
        Get-RoleProblem $Help | Should -Not -BeNullOrEmpty
    }
}
