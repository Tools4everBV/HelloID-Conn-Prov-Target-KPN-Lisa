$Config = $configuration | ConvertFrom-Json
$VerbosePreference = "Continue"

#region functions
function Invoke-LisaRestMethod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $Uri,

        [Parameter(Mandatory = $true)]
        [string]
        $Endpoint,

        [Parameter(Mandatory = $true)]
        [string]
        $Method,

        [Parameter(Mandatory = $false)]
        [string]
        $Body,

        [Parameter(Mandatory = $false)]
        [int]
        $Take = 50,

        [string]
        $AccessToken = $script:accessToken
    )

    try {
        Write-Verbose 'Setting authorizationHeaders'
        $authorizationHeaders = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
        $authorizationHeaders.Add("Authorization", "Bearer $($AccessToken)")
        $authorizationHeaders.Add("Content-Type", "application/json")
        $authorizationHeaders.Add("Mwp-Api-Version", "1.0")

        $requestUrl = "$($Uri)/$($Endpoint)?Top=$take"
        $splatParams = @{
            Uri     = $requestUrl
            Headers = $authorizationHeaders
            Method  = $Method
        }

        if ($Body) {
            Write-Verbose 'Adding body'
            $splatParams['body'] = $body
        }

        $returnValue = [System.Collections.Generic.List[object]]::new()
        do {
            #Set the nextlink token to the Request URL
            if ($rawResult.nextLink) {
                if ($splatParams['Uri'] -match '\?' ) {
                    $splatParams['Uri'] = "$($requestUrl)&SkipToken=$($rawResult.nextLink)"
                }
                else {
                    $splatParams['Uri'] = "$($requestUrl)?SkipToken=$($rawResult.nextLink)"
                }
            }
            $rawResult = Invoke-RestMethod @splatParams

            # Supports Array and single object response!
            if ($rawResult.value -is [Object[]]) {
                Write-Verbose 'Retrieving paged results'
                $returnValue.AddRange($rawResult.value)
            }
            else {
                $returnValue.add($rawResult.value)
            }

        }until([string]::IsNullOrWhiteSpace($rawResult.nextLink))

        Write-Output $returnValue
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}


function Get-LisaAccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]
        $TenantId,

        [Parameter(Mandatory)]
        [string]
        $ClientId,

        [Parameter(Mandatory)]
        [string]
        $ClientSecret,

        [Parameter(Mandatory)]
        [string]
        $Scope
    )

    try {
        $RestMethod = @{
            Uri         = "https://login.microsoftonline.com/$($TenantId)/oauth2/v2.0/token/"
            ContentType = "application/x-www-form-urlencoded"
            Method      = "Post"
            Body        = @{
                grant_type    = "client_credentials"
                client_id     = $ClientId
                client_secret = $ClientSecret
                scope         = $Scope
            }
        }
        Invoke-RestMethod @RestMethod
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
#endregion functions

$splatGetTokenParams = @{
    TenantId     = $Config.TenantId
    ClientId     = $Config.ClientId
    ClientSecret = $Config.ClientSecret
    Scope        = $Config.Scope
}

try {
    $accessToken = (Get-LisaAccessToken @splatGetTokenParams).access_token
}
catch {
    throw "Could not get Lisa AccesToken, $($_)"
}

$splatParams = @{
    Uri         = "$($Config.BaseUrl)"
    Endpoint    = "groups"
    Method      = 'Get'
    AccessToken = $accessToken
}

try {
    $resultGroups = (Invoke-LisaRestMethod @splatParams)
}
catch {
    throw "Could not get Lisa Groups, $($_)"
}

$permissions = $resultGroups | Select-Object @{
    Name       = 'DisplayName'
    Expression = { $_.DisplayName }
}, @{
    Name       = "Identification"
    Expression = { @{Reference = $_.id} }
}


Write-Output ($permissions | ConvertTo-Json -Depth 10)
