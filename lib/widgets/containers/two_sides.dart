// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:flutter/material.dart';

class TwoSides extends StatelessWidget {
  final Widget left;
  final Widget right;
  final double width;
  final double leftWidth;
  final double rightWidht;
  final MainAxisAlignment mainAxisAlignment;
  const TwoSides({
    Key? key,
    required this.left,
    required this.right,
    this.width = 280,
    this.leftWidth = 0,
    this.rightWidht = 0,
    this.mainAxisAlignment = MainAxisAlignment.spaceBetween,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 30,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          // borderRadius: BorderRadius.circular(20),
          color: Color(0xff3B414D),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Row(
            mainAxisAlignment: mainAxisAlignment,
            crossAxisAlignment: CrossAxisAlignment.center,
            verticalDirection: VerticalDirection.down,
            children: <Widget>[
              Container(
                width: leftWidth > 0 ? leftWidth : width / 2,
                child: left,
              ),
              Container(
                width: rightWidht > 0 ? rightWidht : width / 2,
                child: right,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
