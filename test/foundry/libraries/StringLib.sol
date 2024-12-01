// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {console} from "forge-std/console.sol";

library StringLib {
    using StringLib for string;
    using StringLib for uint256;

    bool constant SKIP_FORMATTING = false;
    uint256 constant LABEL_SIZE = 28;
    uint256 constant CELL_SIZE = 40;

    function toString(uint256 value) internal view returns (string memory) {
        return Strings.toString(value);
    }

    function concat(string memory a, string memory b) internal view returns (string memory) {
        return string(abi.encodePacked(a, b));
    }

    function padLeft(uint256 value,  uint256 totalLength) internal view returns (string memory) {
        return value.toString().padLeft(totalLength);
    }

    function padLeft(string memory original,  uint256 totalLength) internal view returns (string memory) {
        return original.padLeft(totalLength, " ");
    }

    function padRight(uint256 value,  uint256 totalLength) internal view returns (string memory) {
        return value.toString().padRight(totalLength);
    }

    function padRight(string memory original,  uint256 totalLength) internal view returns (string memory) {
        return original.padRight(totalLength, " ");
    }

    function padSides(string memory original,  uint256 totalLength) internal view returns (string memory) {
        return original.padSides(totalLength, " ");
    }

    function padLeft(string memory original,  uint256 totalLength, string memory char) internal view returns (string memory) {
        uint256 originalLength = bytes(original).length;
        if (originalLength >= totalLength) {
            return original.truncate(totalLength);
        }

        uint256 extraSpace = totalLength - originalLength;
        string memory whiteSpace = getWhitespace(extraSpace, char);
        return string.concat(whiteSpace, original);
    }

    function padRight(string memory original,  uint256 totalLength, string memory char) internal view returns (string memory) {
        uint256 originalLength = bytes(original).length;
        if (originalLength >= totalLength) {
            return original.truncate(totalLength);
        }

        uint256 extraSpace = totalLength - originalLength;
        string memory whiteSpace = getWhitespace(extraSpace, char);
        return string.concat(original, whiteSpace);
    }


    function padSides(string memory original,  uint256 totalLength, string memory char) internal view returns (string memory) {
        uint256 originalLength = bytes(original).length;
        if (originalLength >= totalLength) {
            return original.truncate(totalLength);
        }

        uint256 extraSpace = totalLength - originalLength;
        uint256 leftExtraSpace = extraSpace / 2;
        uint256 rightExtraSpace = extraSpace - leftExtraSpace;
        string memory leftWhiteSpace = getWhitespace(leftExtraSpace, char);
        string memory rightWhiteSpace = getWhitespace(rightExtraSpace, char);
        return string.concat(leftWhiteSpace, original, rightWhiteSpace);
    }

    function getWhitespace(uint256 size, string memory char) internal view returns (string memory) {
        require(bytes(char).length == 1, "invalid char length");
        string memory whiteSpace = new string(size);
        for (uint256 i=0; i < size; i++) {
            bytes(whiteSpace)[i] = bytes(char)[0];
        }
        return whiteSpace;
    }

    function truncate(string memory original, uint256 length) internal view returns (string memory) {
        bytes memory stringBytes = bytes(original);
        
        if (length > stringBytes.length) {
            length = stringBytes.length;
        }
        
        bytes memory result = new bytes(length);
        for (uint i = 0; i < length; i++) {
            result[i] = stringBytes[i];
        }
        
        return string(result);
    }

    function format(uint256 value, uint8 decimals, uint256 significantDecimals) internal view returns (string memory) {
        if (SKIP_FORMATTING) return value.toString();

        uint256 wholeNumber = value / (10 ** decimals);
        uint256 remainder = value % (10 ** decimals);

        string memory wholeNumberStr = wholeNumber.toString();
        wholeNumberStr = addCommas(wholeNumberStr);

        string memory remainderStr = remainder
            .toString()
            .padLeft(decimals, "0")
            .truncate(significantDecimals);

        return string.concat(wholeNumberStr, ".", remainderStr);
    }

    function formatDollar(uint256 value, uint8 decimals, uint256 significantDecimals) internal view returns (string memory) {
        if (SKIP_FORMATTING) return value.toString();
        return string.concat("$", format(value, decimals, significantDecimals));
    }

    function addCommas(string memory numString) internal view returns (string memory) {
        bytes memory bytesStr = bytes(numString);
        if (bytesStr.length <= 3) {
            return numString; 
        }
    
        uint commasNeeded = (bytesStr.length - 1) / 3;
        uint256 totalLength = bytesStr.length + commasNeeded;
        bytes memory formattedBytes = new bytes(totalLength);

        for (uint i = 0; i < totalLength; i++) {
            uint256 digit = totalLength - i - 1;
            if ((digit + 1) % 4 == 0) {
                formattedBytes[i] = ',';
            } else {
                uint256 commasSoFar = commasNeeded - (digit / 4);
                uint256 j = i - commasSoFar;
                formattedBytes[i] = bytesStr[j];
            }
        }

        return string(formattedBytes);
    }

    function toRow(string[] memory cells) internal view returns (string memory) {
        string memory row = "";
        uint256 length = cells.length;
        for (uint256 i = 0; i < length; i++) {
            if (i < length - 1) {
                row = string.concat(row, cells[i], " ");
            } else {
                row = string.concat(row, cells[i]);
            }
        }
        return row;
    }

    function toRow(string memory label) internal view returns (string memory) {
        string memory row = label.padRight(LABEL_SIZE);
        return row;
    }
    function toRow(string memory label, string memory cell0) internal view returns (string memory) {
        string memory row = label.padRight(LABEL_SIZE);
        row = string.concat(row, " ", cell0.padLeft(CELL_SIZE));
        return row;
    }
    function toRow(string memory label, string memory cell0, string memory cell1) internal view returns (string memory) {
        string memory row = label.padRight(LABEL_SIZE);
        row = string.concat(row, " ", cell0.padLeft(CELL_SIZE));
        row = string.concat(row, " ", cell1.padLeft(CELL_SIZE));
        return row;
    }
    function toRow(string memory label, string memory cell0, string memory cell1, string memory cell2) internal view returns (string memory) {
        string memory row = label.padRight(LABEL_SIZE);
        row = string.concat(row, " ", cell0.padLeft(CELL_SIZE));
        row = string.concat(row, " ", cell1.padLeft(CELL_SIZE));
        row = string.concat(row, " ", cell2.padLeft(CELL_SIZE));
        return row;
    }
    function toRow(string memory label, string memory cell0, string memory cell1, string memory cell2, string memory cell3) internal view returns (string memory) {
        string memory row = label.padRight(LABEL_SIZE);
        row = string.concat(row, " ", cell0.padLeft(CELL_SIZE));
        row = string.concat(row, " ", cell1.padLeft(CELL_SIZE));
        row = string.concat(row, " ", cell2.padLeft(CELL_SIZE));
        row = string.concat(row, " ", cell3.padLeft(CELL_SIZE));
        return row;
    }
    function toRow(string memory label, string memory cell0, string memory cell1, string memory cell2, string memory cell3, string memory cell4) internal view returns (string memory) {
        string memory row = label.padRight(LABEL_SIZE);
        row = string.concat(row, " ", cell0.padLeft(CELL_SIZE));
        row = string.concat(row, " ", cell1.padLeft(CELL_SIZE));
        row = string.concat(row, " ", cell2.padLeft(CELL_SIZE));
        row = string.concat(row, " ", cell3.padLeft(CELL_SIZE));
        row = string.concat(row, " ", cell4.padLeft(CELL_SIZE));
        return row;
    }

    function toHeader(string memory label0) internal view returns (string memory) {
        string memory row = label0.padRight(LABEL_SIZE);
        return row;
    }
    function toHeader(string memory label0, string memory label1) internal view returns (string memory) {
        string memory row = label0.padRight(LABEL_SIZE);
        row = string.concat(row, " ", label1.padSides(CELL_SIZE));
        return row;
    }
    function toHeader(string memory label0, string memory label1, string memory label2) internal view returns (string memory) {
        string memory row = label0.padRight(LABEL_SIZE);
        row = string.concat(row, " ", label1.padSides(CELL_SIZE));
        row = string.concat(row, " ", label2.padSides(CELL_SIZE));
        return row;
    }
    function toHeader(string memory label0, string memory label1, string memory label2, string memory label3) internal view returns (string memory) {
        string memory row = label0.padRight(LABEL_SIZE);
        row = string.concat(row, " ", label1.padSides(CELL_SIZE));
        row = string.concat(row, " ", label2.padSides(CELL_SIZE));
        row = string.concat(row, " ", label3.padSides(CELL_SIZE));
        return row;
    }
    function toHeader(string memory label0, string memory label1, string memory label2, string memory label3, string memory label4) internal view returns (string memory) {
        string memory row = label0.padRight(LABEL_SIZE);
        row = string.concat(row, " ", label1.padSides(CELL_SIZE));
        row = string.concat(row, " ", label2.padSides(CELL_SIZE));
        row = string.concat(row, " ", label3.padSides(CELL_SIZE));
        row = string.concat(row, " ", label4.padSides(CELL_SIZE));
        return row;
    }
    function toHeader(string memory label0, string memory label1, string memory label2, string memory label3, string memory label4, string memory label5) internal view returns (string memory) {
        string memory row = label0.padRight(LABEL_SIZE);
        row = string.concat(row, " ", label1.padSides(CELL_SIZE));
        row = string.concat(row, " ", label2.padSides(CELL_SIZE));
        row = string.concat(row, " ", label3.padSides(CELL_SIZE));
        row = string.concat(row, " ", label4.padSides(CELL_SIZE));
        row = string.concat(row, " ", label5.padSides(CELL_SIZE));
        return row;
    }
}
