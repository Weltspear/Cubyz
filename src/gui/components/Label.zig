const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const graphics = main.graphics;
const draw = graphics.draw;
const TextBuffer = graphics.TextBuffer;
const vec = main.vec;
const Vec2f = vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;

const Label = @This();

const fontSize: f32 = 16;

pos: Vec2f,
size: Vec2f,
text: TextBuffer,

pub fn init(pos: Vec2f, maxWidth: f32, text: []const u8, alignment: TextBuffer.Alignment) Allocator.Error!*Label {
	const self = try gui.allocator.create(Label);
	self.* = Label {
		.text = try TextBuffer.init(gui.allocator, text, .{}, false, alignment),
		.pos = pos,
		.size = undefined,
	};
	self.size = try self.text.calculateLineBreaks(fontSize, maxWidth);
	return self;
}

pub fn deinit(self: *const Label) void {
	self.text.deinit();
	gui.allocator.destroy(self);
}

pub fn toComponent(self: *Label) GuiComponent {
	return GuiComponent{
		.label = self
	};
}

pub fn updateText(self: *Label, newText: []const u8) !void {
	const alignment = self.text.alignment;
	self.text.deinit();
	self.text = try TextBuffer.init(gui.allocator, newText, .{}, false, alignment);
	self.size = try self.text.calculateLineBreaks(fontSize, self.size[0]);
}

pub fn render(self: *Label, _: Vec2f) !void {
	try self.text.render(self.pos[0], self.pos[1], fontSize);
}