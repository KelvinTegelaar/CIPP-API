function Search-GitHubRepository {
    [CmdletBinding()]
    Param (
        [string[]]$Repository,
        [string]$Path,
        [string]$SearchTerm,
        [string]$Language,
        [string]$Type = 'code'
    )
    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json).GitHub

    $QueryParts = [System.Collections.Generic.List[string]]::new()
    if ($Repository) {
        $RepoParts = [System.Collections.Generic.List[string]]::new()
        foreach ($Repo in $Repository) {
            $RepoParts.Add("repo:$Repo")
        }
        if (($RepoParts | Measure-Object).Count -gt 1) {
            $QueryParts.Add('(' + ($RepoParts -join ' OR ') + ')')
        } else {
            $QueryParts.Add($RepoParts[0])
        }
    }
    if ($Path) {
        $QueryParts.Add("path:$Path")
    }
    if ($SearchTerm) {
        $QueryParts.Add("`"$SearchTerm`"")
    }
    if ($Language) {
        $QueryParts.Add("language:$Language")
    }

    $Query = $QueryParts -join ' '
    Write-Information "Query: $Query"
    Invoke-GitHubApiRequest -Configuration $Configuration -Path "search/$($Type)?q=$($Query)" -Method GET
}
