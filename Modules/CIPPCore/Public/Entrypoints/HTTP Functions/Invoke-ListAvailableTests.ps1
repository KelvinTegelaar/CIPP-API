function Invoke-ListAvailableTests {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Dashboard.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $Request.Headers.'x-ms-client-principal' -API $APIName -message 'Accessed this API' -Sev 'Debug'

    try {
        # Get all test folders
        $TestFolders = Get-ChildItem 'Modules\CIPPCore\Public\Tests' -Directory

        # Build identity tests array
        $IdentityTests = foreach ($TestFolder in $TestFolders) {
            $IdentityTestFiles = Get-ChildItem "$($TestFolder.FullName)\Identity\*.ps1" -ErrorAction SilentlyContinue
            foreach ($TestFile in $IdentityTestFiles) {
                # Extract test ID from filename (e.g., Invoke-CippTestZTNA21772.ps1 -> ZTNA21772)
                if ($TestFile.BaseName -match 'Invoke-CippTest(.+)$') {
                    $TestId = $Matches[1]

                    # Try to get test metadata from the file
                    $TestContent = Get-Content $TestFile.FullName -Raw
                    $TestName = $TestId

                    # Try to extract Synopsis from comment-based help
                    if ($TestContent -match '\.SYNOPSIS\s+(.+?)(?=\s+\.|\s+#>|\s+\[)') {
                        $TestName = $Matches[1].Trim()
                    }

                    [PSCustomObject]@{
                        id         = $TestId
                        name       = $TestName
                        category   = 'Identity'
                        testFolder = $TestFolder.Name
                    }
                }
            }
        }

        # Build device tests array
        $DevicesTests = foreach ($TestFolder in $TestFolders) {
            $DeviceTestFiles = Get-ChildItem "$($TestFolder.FullName)\Devices\*.ps1" -ErrorAction SilentlyContinue
            foreach ($TestFile in $DeviceTestFiles) {
                if ($TestFile.BaseName -match 'Invoke-CippTest(.+)$') {
                    $TestId = $Matches[1]

                    $TestContent = Get-Content $TestFile.FullName -Raw
                    $TestName = $TestId

                    if ($TestContent -match '\.SYNOPSIS\s+(.+?)(?=\s+\.|\s+#>|\s+\[)') {
                        $TestName = $Matches[1].Trim()
                    }

                    [PSCustomObject]@{
                        id         = $TestId
                        name       = $TestName
                        category   = 'Devices'
                        testFolder = $TestFolder.Name
                    }
                }
            }
        }

        $Body = [PSCustomObject]@{
            IdentityTests = $IdentityTests
            DevicesTests  = $DevicesTests
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Body = [PSCustomObject]@{
            Results = "Failed to list available tests: $($ErrorMessage.NormalizedError)"
        }
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = ConvertTo-Json -InputObject $Body -Depth 10
        })
}
