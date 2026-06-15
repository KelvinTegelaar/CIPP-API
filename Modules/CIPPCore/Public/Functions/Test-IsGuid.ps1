function Test-IsGuid {
    <#
    .SYNOPSIS
        Tests if a string is a valid GUID
    .DESCRIPTION
        This function checks if a string can be parsed as a valid GUID using .NET's Guid.TryParse method.
    .PARAMETER String
        The string to test for GUID format
    .FUNCTIONALITY
        Internal
    .EXAMPLE
        Test-IsGuid -String "123e4567-e89b-12d3-a456-426614174000"
    .EXAMPLE
        Test-IsGuid -String "not-a-guid"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$String
    )

    return [guid]::TryParse($String, [ref][guid]::Empty)
}
