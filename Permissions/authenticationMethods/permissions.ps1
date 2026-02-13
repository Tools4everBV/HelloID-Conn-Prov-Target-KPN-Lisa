#################################################
# HelloID-Conn-Prov-Target-KPN-Lisa-Permissions-AuthenticationMethods-List
# List authentication methods as permissions
# PowerShell V2
#################################################
# Please see the KPN Lisa API docs: https://mwpapi.kpnwerkplek.com/index.html
# Supported phone types: mobile, alternateMobile, office
# Supported email type: email

# Phone authentication methods
$outputContext.Permissions.Add(
    @{
        DisplayName    = "Phone authentication method - mobile"
        Identification = @{
            Reference = "3179e48a-750b-4051-897c-87b9720928f7"
            Type      = "mobile"
            Method    = "phone"
        }
    }
)

$outputContext.Permissions.Add(
    @{
        DisplayName    = "Phone authentication method - alternateMobile"
        Identification = @{
            Reference = "b6332ec1-7057-4abe-9331-3d72feddfe41"
            Type      = "alternateMobile"
            Method    = "phone"
        }
    }
)

$outputContext.Permissions.Add(
    @{
        DisplayName    = "Phone authentication method - office"
        Identification = @{
            Reference = "e37fc753-ff3b-4958-9484-eaa9425c82bc"
            Type      = "office"
            Method    = "phone"
        }
    }
)

# Email authentication methods
$outputContext.Permissions.Add(
    @{
        DisplayName    = "Email authentication method - email"
        Identification = @{
            Reference = "3ddfcfc8-9383-446f-83cc-3ab9be4be18f"
            Type      = "email"
            Method    = "email"
        }
    }
)
