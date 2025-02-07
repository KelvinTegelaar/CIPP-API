function Search-GitHub {
    [CmdletBinding()]
    Param (
        [string[]]$Repository,
        [string[]]$User,
        [string]$Path,
        [string[]]$SearchTerm,
        [string]$Language,
        [ValidateSet('code', 'commits', 'issues', 'users', 'repositories', 'topics', 'labels')]
        [string]$Type = 'code'
    )

    $QueryParts = [System.Collections.Generic.List[string]]::new()
    if ($SearchTerm) {
        $SearchTermParts = [System.Collections.Generic.List[string]]::new()
        foreach ($Term in $SearchTerm) {
            $SearchTermParts.Add("`"$Term`"")
        }
        if (($SearchTermParts | Measure-Object).Count -gt 1) {
            $QueryParts.Add(($SearchTermParts -join ' OR '))
        } else {
            $QueryParts.Add($SearchTermParts[0])
        }
    }
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
    if ($User) {
        $UserParts = [System.Collections.Generic.List[string]]::new()
        foreach ($U in $User) {
            $UserParts.Add("user:$U")
        }
        if (($UserParts | Measure-Object).Count -gt 1) {
            $QueryParts.Add('(' + ($UserParts -join ' OR ') + ')')
        } else {
            $QueryParts.Add($UserParts[0])
        }
    }
    if ($Path) {
        $QueryParts.Add("path:$Path")
    }
    if ($Language) {
        $QueryParts.Add("language:$Language")
    }

    $Query = $QueryParts -join ' '
    Write-Information "Query: $Query"
    Invoke-GitHubApiRequest -Path "search/$($Type)?q=$($Query)" -Method GET
}
