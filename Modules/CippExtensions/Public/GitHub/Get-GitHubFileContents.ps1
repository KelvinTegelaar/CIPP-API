function Get-GitHubFileContents {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        $FullName,

        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        $Path,

        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        $Branch
    )

    process {
        $Path = "repos/$($FullName)/contents/$($Path)?ref=$($Branch)"
        #Write-Information $Path
        $File = Invoke-GitHubApiRequest -Path $Path -Method GET
        $content = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($File.content))
        #If the first character is a BOM, remove it
        if ($content[0] -eq [char]65279) { $content = $content.Substring(1) }
        return [PSCustomObject]@{
            name    = $File.name
            path    = $File.path
            content = $content
            sha     = $File.sha
            size    = $File.size
        }
    }
}
