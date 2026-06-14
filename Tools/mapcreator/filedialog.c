#include <windows.h>
#include <stdio.h>

int main(void) {
    OPENFILENAMEW ofn = {0};
    WCHAR filePath[MAX_PATH] = {0};

    ofn.lStructSize = sizeof(ofn);
    ofn.hwndOwner = NULL;
    ofn.lpstrFilter = L"PNG files (*.png)\0*.png\0All files (*.*)\0*.*\0";
    ofn.lpstrFile = filePath;
    ofn.nMaxFile = MAX_PATH;
    ofn.Flags = OFN_FILEMUSTEXIST | OFN_HIDEREADONLY;
    ofn.lpstrTitle = L"Select map image";
    ofn.lpstrInitialDir = NULL;

    if (GetOpenFileNameW(&ofn)) {
        wprintf(L"%s", filePath);
        return 0;
    }
    return 1;
}