import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ChatTextField extends StatefulWidget {
  final TextEditingController? controller;

  final void Function(String)? onChanged;
  final void Function()? onEditingComplete;

  final Widget? prefixIcon;
  final Widget? suffixIcon;

  const ChatTextField({
    super.key,
    this.controller,
    this.onChanged,
    this.onEditingComplete,
    this.prefixIcon,
    this.suffixIcon,
  });

  @override
  State<ChatTextField> createState() => _ChatTextFieldState();
}

class _ChatTextFieldState extends State<ChatTextField> {
  static final _textFieldBucket = PageStorageBucket();

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller?.text = _readTextFieldState();
      widget.onChanged?.call(widget.controller?.text ?? '');
    });
  }

  @override
  void deactivate() {
    // Write the latest text to the bucket
    _writeTextFieldState(widget.controller?.text ?? '');

    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        SingleActivator(LogicalKeyboardKey.enter, shift: true): () {
          widget.controller?.text += '\n';
        },
      },
      child: TextField(
        controller: widget.controller,
        onChanged: widget.onChanged,
        onEditingComplete: widget.onEditingComplete,
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: 'Message',
          prefixIcon: widget.prefixIcon,
          suffixIcon: widget.suffixIcon,
          contentPadding: const EdgeInsets.only(left: 4, right: 4, top: 14, bottom: 8),
          isDense: true,
        ),
        minLines: 1,
        maxLines: 5,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: _textInputAction,
        onTapOutside: (PointerDownEvent event) {
          FocusManager.instance.primaryFocus?.unfocus();
        },
      ),
    );
  }

  TextInputAction get _textInputAction => TextInputAction.send;

  String _readTextFieldState() {
    return _textFieldBucket.readState(context, identifier: widget.key) ?? '';
  }

  void _writeTextFieldState(String text) {
    if (widget.key == null) return;

    if (widget.key is ValueKey && (widget.key as ValueKey).value == null) {
      return;
    }

    _textFieldBucket.writeState(context, text, identifier: widget.key);
  }
}
