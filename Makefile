include $(TOPDIR)/rules.mk

PKG_NAME:=hop
PKG_VERSION:=0.2.0
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/oslo254804746/hop-rs.git
PKG_SOURCE_DATE:=$(HOP_SOURCE_DATE)
PKG_SOURCE_VERSION:=$(HOP_SOURCE_VERSION)
PKG_MIRROR_HASH:=$(HOP_MIRROR_HASH)

PKG_MAINTAINER:=Hop maintainers
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_BUILD_DEPENDS:=rust/host
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk

define Package/hop
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=SSH
  TITLE:=Small, complete SSH jump server
  URL:=https://github.com/oslo254804746/hop-rs
  DEPENDS:=$(RUST_ARCH_DEPENDS) +libgcc +libpthread
  USERID:=hop=514:hop=514
endef

define Package/hop/description
 Hop is a single-binary SSH jump server with a SQLite resource catalog,
 native SSH/SFTP/ProxyJump support, and optional loopback Control API.
endef

define Package/hop/conffiles
/etc/config/hop
/etc/hop/config.toml
endef

define Build/Compile
	$(call Build/Compile/Cargo,crates/hop-server)
endef

define Package/hop/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/bin/hop-server $(1)/usr/bin/hop-server
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/hop.init $(1)/etc/init.d/hop
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/hop.uci $(1)/etc/config/hop
	$(INSTALL_DIR) $(1)/etc/hop
	$(INSTALL_CONF) ./files/hop.toml $(1)/etc/hop/config.toml
	$(INSTALL_DIR) $(1)/var/lib/hop
endef

$(eval $(call BuildPackage,hop))
