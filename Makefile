include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-hop
PKG_VERSION:=0.2.4
PKG_RELEASE:=1
PKG_MAINTAINER:=Hop maintainers
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-hop
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI support for Hop
  URL:=https://github.com/oslo254804746/luci-app-hop
  PKGARCH:=all
  EXTRA_DEPENDS:=luci-base (>=0), ucode-mod-socket (>=0), curl (>=0), ca-bundle (>=0)
  USERID:=hop=514:hop=514
endef

define Package/luci-app-hop/description
 Lightweight LuCI and procd integration for Hop. The architecture-specific
 Hop core is downloaded separately from verified GitHub Release assets.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/luci-app-hop/conffiles
/etc/config/hop
/etc/hop/config.toml
endef

define Package/luci-app-hop/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/hop $(1)/etc/config/hop
	$(INSTALL_DIR) $(1)/etc/hop
	$(INSTALL_CONF) ./root/etc/hop/config.toml $(1)/etc/hop/config.toml
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/hop $(1)/etc/init.d/hop
	$(INSTALL_DIR) $(1)/usr/share/hop
	$(INSTALL_BIN) ./root/usr/share/hop/hop-core $(1)/usr/share/hop/hop-core
	$(INSTALL_DIR) $(1)/usr/share/hop/panel
	$(INSTALL_DATA) ./root/usr/share/hop/panel/index.html \
		$(1)/usr/share/hop/panel/index.html
	$(INSTALL_DIR) $(1)/usr/share/ucode/luci/controller
	$(INSTALL_DATA) ./ucode/controller/hop.uc \
		$(1)/usr/share/ucode/luci/controller/hop.uc
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-hop.json \
		$(1)/usr/share/luci/menu.d/luci-app-hop.json
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-hop.json \
		$(1)/usr/share/rpcd/acl.d/luci-app-hop.json
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/hop
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/hop/settings.js \
		$(1)/www/luci-static/resources/view/hop/settings.js
	$(INSTALL_DIR) $(1)/www/hop/assets
	$(CP) ./htdocs/hop/assets/. $(1)/www/hop/assets/
endef

$(eval $(call BuildPackage,luci-app-hop))
