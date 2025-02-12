function Push-GitHubContent {
    <#
    .SYNOPSIS
        Update file content in GitHub repository
    .DESCRIPTION
        Update file content in GitHub repository
    .PARAMETER FullName
        The full name of the repository (e.g. 'octocat/Hello-World')
    .PARAMETER Path
        The path to the file in the repository
    .PARAMETER Branch
        The branch to update the file in (default: 'main')
    .PARAMETER Content
        The new content of the file
    .PARAMETER Message
        The commit message
    .EXAMPLE
        Push-GitHubContent -FullName 'octocat/Hello-World' -Path 'README.md' -Content 'Hello, World!' -Message 'Update README.md'
    #>
    [CmdletBinding()]
    param (
        [string]$FullName,
        [string]$Path,
        [string]$Branch = 'main',
        [string]$Content,
        [string]$Message
    )

    $ContentBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Content))
    try {
        $ContentSha = (Invoke-GitHubApiRequest -Path "repos/$($FullName)/contents/$($Path)?ref=$($Branch)").sha
    } catch {
        $ContentSha = $null
    }
    $Filename = Split-Path $Path -Leaf

    $Body = @{
        message = $Message ?? "Update $($Filename)"
        content = $ContentBase64
        branch  = $Branch
    }
    if ($ContentSha) {
        $Body.sha = $ContentSha
    }

    Invoke-GitHubApiRequest -Path "repos/$($FullName)/contents/$($Path)" -Method PUT -Body $Body
}
