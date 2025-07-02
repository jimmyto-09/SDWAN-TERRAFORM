variable "vnf_sites" {
  description = "Mapa de configuración por sitio"
  type = map(object({
    netnum     = number
    custunip   = string
    vnftunip   = string
    custprefix = string
    vcpepubip  = string
    vcpegw     = string
    remotesite=string
  }))
}
