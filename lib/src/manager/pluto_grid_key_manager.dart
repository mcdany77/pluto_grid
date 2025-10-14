import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:rxdart/rxdart.dart';

/// 2021-11-19
/// KeyEventResult.skipRemainingHandlers 동작 오류로 인한 임시 코드
/// 이슈 해결 후 : 삭제
///
/// desktop 에서만 발생
/// skipRemainingHandlers 을 리턴하면 pluto_grid.dart 의 FocusScope 의
/// 콜백이 호출 되지 않고 TextField 에 키 입력이 되어야 하는데
/// 방향키, 백스페이스 등이 입력되지 않음.(문자등은 입력 됨)
/// https://github.com/flutter/flutter/issues/93873
class PlutoGridKeyEventResult {
  bool _skip = false;

  bool get isSkip => _skip;

  KeyEventResult skip(KeyEventResult result) {
    _skip = true;

    return result;
  }

  KeyEventResult consume(KeyEventResult result) {
    if (_skip) {
      _skip = false;

      return KeyEventResult.ignored;
    }

    return result;
  }
}

class PlutoGridKeyManager {
  PlutoGridStateManager stateManager;

  PlutoGridKeyEventResult eventResult = PlutoGridKeyEventResult();

  PlutoGridKeyManager({
    required this.stateManager,
  });

  final PublishSubject<PlutoKeyManagerEvent> _subject =
      PublishSubject<PlutoKeyManagerEvent>();

  PublishSubject<PlutoKeyManagerEvent> get subject => _subject;

  late final StreamSubscription _subscription;

  StreamSubscription get subscription => _subscription;

  void dispose() {
    _subscription.cancel();

    _subject.close();
  }

  void init() {
    final normalStream = _subject.stream.where((event) => !event.needsThrottle);

    final movingStream =
        _subject.stream.where((event) => event.needsThrottle).transform(
              ThrottleStreamTransformer(
                (_) => TimerStream(_, const Duration(milliseconds: 1)),
              ),
            );

    _subscription = MergeStream([normalStream, movingStream]).listen(_handler);
  }

  void _handler(PlutoKeyManagerEvent keyEvent) {
    if (keyEvent.isKeyUpEvent) return;

    if (stateManager.configuration.shortcut.handle(
      keyEvent: keyEvent,
      stateManager: stateManager,
      state: HardwareKeyboard.instance,
    )) {
      return;
    }

    _handleDefaultActions(keyEvent);
  }

  void _handleDefaultActions(PlutoKeyManagerEvent keyEvent) {
    // Check for character input (including numpad digits)
    // Allow Shift key for uppercase letters, but block other modifiers
    if (_isInputCharacter(keyEvent) && 
        (!keyEvent.isModifierPressed || _isShiftOnlyForLetter(keyEvent))) {
      _handleCharacter(keyEvent);
      return;
    }
  }

  bool _isShiftOnlyForLetter(PlutoKeyManagerEvent keyEvent) {
    // Allow Shift key only if it's used for typing letters (not Ctrl+Shift, Alt+Shift, etc.)
    return keyEvent.isShiftPressed && 
           !keyEvent.isCtrlPressed && 
           !keyEvent.isAltPressed &&
           _isLetter(keyEvent);
  }

  bool _isLetter(PlutoKeyManagerEvent keyEvent) {
    // Check if the key is a letter (A-Z)
    final keyId = keyEvent.event.logicalKey.keyId;
    return (keyId >= 0x0000000041 && keyId <= 0x000000005a) || // A-Z
           (keyId >= 0x0000000061 && keyId <= 0x000000007a);   // a-z
  }

  bool _isInputCharacter(PlutoKeyManagerEvent keyEvent) {
    // Check if it's a regular character with a character value
    if (keyEvent.isCharacter && keyEvent.event.character != null) {
      return true;
    }
    
    // Check if it's a numpad digit (even if character is null)
    if (keyEvent.isNumpadDigit) {
      return true;
    }
    
    return false;
  }

  void _handleCharacter(PlutoKeyManagerEvent keyEvent) {
    if (stateManager.isEditing != true && stateManager.currentCell != null) {
      stateManager.setEditing(true);

      // Get character from event or from numpad mapping
      String? character = keyEvent.event.character;
      if (character == null && keyEvent.isNumpadDigit) {
        character = keyEvent.getNumpadDigitCharacter();
      }

      if (character == null) {
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (stateManager.textEditingController != null && character != null) {
          stateManager.textEditingController!.text = character;
          // Position cursor at the end to prevent text selection overwrites
          stateManager.textEditingController!.selection = TextSelection.fromPosition(
            TextPosition(offset: character.length),
          );
          
          // Set cursor position again in the next frame to ensure it overrides
          // any automatic text selection that might happen after this
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (stateManager.textEditingController != null) {
              stateManager.textEditingController!.selection = TextSelection.fromPosition(
                TextPosition(offset: stateManager.textEditingController!.text.length),
              );
            }
          });
        }
      });
    }
  }
}
