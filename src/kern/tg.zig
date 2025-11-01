const XdpAction = enum(c_long) {
    XDP_ABORTED,
    XDP_DROP,
    XDP_PASS,
    XDP_TX,
    XDP_REDIRECT,
};

export const _license linksection("license") = "GPL".*;

export fn tg_pass() linksection("xdp.frags") c_long {
    return @intFromEnum(XdpAction.XDP_PASS);
}

export fn tg_drop() linksection("xdp.frags") c_long {
    return @intFromEnum(XdpAction.XDP_DROP);
}
